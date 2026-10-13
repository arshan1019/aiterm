package com.aiterm.aiterm

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.atomic.AtomicInteger

/**
 * Bridges lib/core/pty_channel.dart to [ShellSession]. One MethodChannel
 * ("aiterm/pty") for control, one EventChannel ("aiterm/pty/output") for
 * streaming bytes back out, keyed by session id (see PtySession.start on
 * the Dart side, which passes its id as the EventChannel listen argument).
 */
class PtyPlugin : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sessions = mutableMapOf<Int, ShellSession>()
    private val sinks = mutableMapOf<Int, EventChannel.EventSink>()
    private val nextId = AtomicInteger(1)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val argv = (call.argument<List<String>>("argv")) ?: emptyList()
                @Suppress("UNCHECKED_CAST")
                val env = (call.argument<Map<String, String>>("env")) ?: emptyMap()
                val cwd = call.argument<String>("cwd") ?: "/"
                val rows = call.argument<Int>("rows") ?: 24
                val cols = call.argument<Int>("cols") ?: 80
                val id = nextId.getAndIncrement()

                val session = ShellSession(
                    argv = argv,
                    env = env,
                    cwd = cwd,
                    rows = rows,
                    cols = cols,
                    onData = { bytes ->
                        mainHandler.post { sinks[id]?.success(bytes) }
                    },
                    onExit = { code ->
                        mainHandler.post {
                            sinks[id]?.success(mapOf("exitCode" to code))
                        }
                    },
                )
                try {
                    session.start()
                    sessions[id] = session
                    result.success(mapOf("id" to id))
                } catch (e: Exception) {
                    result.error("start_failed", e.message, null)
                }
            }
            "write" -> {
                val id = call.argument<Int>("id") ?: return result.success(null)
                val data = call.argument<String>("data") ?: ""
                sessions[id]?.write(data)
                result.success(null)
            }
            "resize" -> {
                val id = call.argument<Int>("id") ?: return result.success(null)
                val rows = call.argument<Int>("rows") ?: 24
                val cols = call.argument<Int>("cols") ?: 80
                sessions[id]?.resize(rows, cols)
                result.success(null)
            }
            "stop" -> {
                val id = call.argument<Int>("id") ?: return result.success(null)
                sessions.remove(id)?.stop()
                sinks.remove(id)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val id = (arguments as? Int) ?: return
        sinks[id] = events
    }

    override fun onCancel(arguments: Any?) {
        val id = (arguments as? Int) ?: return
        sinks.remove(id)
    }
}
