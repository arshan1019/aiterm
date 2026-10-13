package com.aiterm.aiterm

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Bridges lib/platform/pty.dart to [ShellSession].
 *
 * "aiterm/pty" is the control channel. "aiterm/pty/output" is a single
 * stream shared by every session: an EventChannel supports one listener,
 * so events carry the session id — `[id, bytes]` for output and
 * `[id, exitCode]` when the process ends.
 *
 * Output is batched: the reader thread appends to the session's outbox and
 * schedules at most one flush per main-loop turn, so a burst (a build log,
 * `cat` of a big file) becomes a few large messages instead of thousands
 * of small ones. Writes go through a background thread so a full PTY
 * buffer can never stall the UI thread.
 */
class PtyPlugin : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val sessions = mutableMapOf<Int, ShellSession>()
    private val outboxes = mutableMapOf<Int, Outbox>()
    private val nextId = AtomicInteger(1)
    private var sink: EventChannel.EventSink? = null

    private class Outbox {
        val bytes = ByteArrayOutputStream()
        var scheduled = false
        var exitCode: Int? = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            "write" -> {
                val session = sessions[call.argument<Int>("id")]
                val data = call.argument<String>("data") ?: ""
                if (session != null) io.execute { session.write(data) }
                result.success(null)
            }
            "resize" -> {
                sessions[call.argument<Int>("id")]?.resize(
                    call.argument<Int>("rows") ?: 24,
                    call.argument<Int>("cols") ?: 80,
                )
                result.success(null)
            }
            "stop" -> {
                val id = call.argument<Int>("id")
                sessions.remove(id)?.stop()
                outboxes.remove(id)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val id = nextId.getAndIncrement()
        val outbox = Outbox()
        outboxes[id] = outbox
        val session = ShellSession(
            argv = call.argument<List<String>>("argv") ?: emptyList(),
            env = call.argument<Map<String, String>>("env") ?: emptyMap(),
            cwd = call.argument<String>("cwd") ?: "/",
            rows = call.argument<Int>("rows") ?: 24,
            cols = call.argument<Int>("cols") ?: 80,
            onData = { bytes -> enqueue(id, outbox) { it.bytes.write(bytes) } },
            onExit = { code -> enqueue(id, outbox) { it.exitCode = code } },
        )
        try {
            session.start()
            sessions[id] = session
            result.success(mapOf("id" to id))
        } catch (e: Exception) {
            outboxes.remove(id)
            result.error("start_failed", e.message, null)
        }
    }

    /** Called on the reader thread. */
    private fun enqueue(id: Int, outbox: Outbox, change: (Outbox) -> Unit) {
        synchronized(outbox) {
            change(outbox)
            if (outbox.scheduled) return
            outbox.scheduled = true
        }
        main.post { flush(id, outbox) }
    }

    private fun flush(id: Int, outbox: Outbox) {
        if (outboxes[id] !== outbox) return // session was stopped
        val events = sink ?: return // kept until Dart listens; see onListen
        val data: ByteArray
        val exit: Int?
        synchronized(outbox) {
            data = outbox.bytes.toByteArray()
            outbox.bytes.reset()
            exit = outbox.exitCode
            outbox.scheduled = false
        }
        if (data.isNotEmpty()) events.success(listOf(id, data))
        if (exit != null) {
            events.success(listOf(id, exit))
            sessions.remove(id)
            outboxes.remove(id)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        outboxes.toList().forEach { (id, outbox) -> flush(id, outbox) }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }
}
