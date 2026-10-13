package com.aiterm.aiterm

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Owns every terminal session for the life of the process, not of the UI:
 * when the activity (and its Flutter engine) goes away, shells keep running
 * under [SessionService], and the next UI reattaches with [attach].
 *
 * Output is batched per main-loop turn into one event stream
 * (`[id, bytes]` / `[id, exitCode]`), and each session keeps an
 * [OutputRing] of recent output for redrawing after a reattach.
 */
object SessionRegistry {
    private const val RING_BYTES = 512 * 1024

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val nextId = AtomicInteger(1)
    private val sessions = mutableMapOf<Int, Entry>()
    private var sink: EventChannel.EventSink? = null
    private var appContext: Context? = null

    /** The session the user is looking at, or null when the app is hidden. */
    @Volatile private var visibleId: Int? = null

    private class Entry(val session: ShellSession) {
        val ring = OutputRing(RING_BYTES)
        val signals = TerminalSignals()
        val policy = NotifyPolicy()
        @Volatile var title = "Terminal"
        val pending = ByteArrayOutputStream()
        var scheduled = false
        var exitCode: Int? = null
    }

    val count: Int get() = sessions.size

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    /** Called on the main thread. Returns the new session's id. */
    fun start(argv: List<String>, env: Map<String, String>, cwd: String, rows: Int, cols: Int): Int {
        val id = nextId.getAndIncrement()
        lateinit var entry: Entry
        val session = ShellSession(
            argv, env, cwd, rows, cols,
            onData = { bytes ->
                notifyFor(id, entry, bytes)
                enqueue(id, entry) { it.ring.append(bytes); it.pending.write(bytes) }
            },
            onExit = { code -> enqueue(id, entry) { it.exitCode = code } },
        )
        entry = Entry(session)
        session.start()
        sessions[id] = entry
        updateService()
        return id
    }

    fun write(id: Int, data: String) {
        val e = sessions[id] ?: return
        val s = e.session
        if ('\r' in data) synchronized(e.policy) { e.policy.onEnter() }
        io.execute { s.write(data) }
    }

    fun resize(id: Int, rows: Int, cols: Int) {
        sessions[id]?.session?.resize(rows, cols)
    }

    fun stop(id: Int) {
        sessions.remove(id)?.session?.stop()
        updateService()
    }

    /** Hangs up every shell; each then exits through the normal path. */
    fun stopAll() {
        sessions.values.forEach { it.session.stop() }
    }

    fun setVisible(id: Int?) {
        visibleId = id
        val ctx = appContext
        if (id != null && ctx != null) SessionNotifier.cancel(ctx, id)
    }

    fun setTitle(id: Int, title: String) {
        sessions[id]?.title = title
    }

    /** Reader thread: notifications are decided natively, UI or not. */
    private fun notifyFor(id: Int, e: Entry, bytes: ByteArray) {
        val ctx = appContext ?: return
        val signals = e.signals.feed(bytes)
        if (signals.isEmpty()) return
        val visibility = Visibility(visibleId == id)
        for (signal in signals) {
            val spec = synchronized(e.policy) { e.policy.onSignal(signal, visibility, e.signals.lastLine(), e.title) }
            if (spec != null) SessionNotifier.show(ctx, id, spec)
        }
    }

    fun live(): List<Int> = sessions.filterValues { it.exitCode == null }.keys.toList()

    /** Recent output to redraw a reattached terminal; null if [id] is gone. */
    fun attach(id: Int): ByteArray? {
        val e = sessions[id] ?: return null
        // Pending bytes are already in the ring; don't send them twice.
        synchronized(e) { e.pending.reset() }
        return e.ring.snapshot()
    }

    fun setSink(events: EventChannel.EventSink?) {
        sink = events
        if (events != null) sessions.toList().forEach { (id, e) -> flush(id, e) }
    }

    /** Reader thread. */
    private fun enqueue(id: Int, e: Entry, change: (Entry) -> Unit) {
        synchronized(e) {
            change(e)
            if (e.scheduled) return
            e.scheduled = true
        }
        main.post { flush(id, e) }
    }

    private fun flush(id: Int, e: Entry) {
        if (sessions[id] !== e) return // stopped
        val events = sink
        var data = ByteArray(0)
        val exit: Int?
        synchronized(e) {
            e.scheduled = false
            exit = e.exitCode
            // With no UI listening, output waits in `pending` (and the ring).
            if (events != null) {
                data = e.pending.toByteArray()
                e.pending.reset()
            }
        }
        if (events != null && data.isNotEmpty()) events.success(listOf(id, data))
        if (exit != null) {
            events?.success(listOf(id, exit))
            // Gone either way; a UI that reattaches later restores it cold.
            sessions.remove(id)
            updateService()
        }
    }

    private fun updateService() {
        val ctx = appContext ?: return
        SessionService.update(ctx, sessions.size)
    }
}
