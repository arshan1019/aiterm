package com.aiterm.aiterm

/** Whether the user can currently see this session. */
data class Visibility(val visible: Boolean)

data class NotificationSpec(val title: String, val body: String)

/**
 * When a session deserves a notification: a long command finishing (shell
 * integration prompt marks), a program asking (OSC 9 / OSC 777, which
 * Claude Code can send), or a bell, which many tools ring when they need
 * input. Never for the tab the user is looking at.
 */
class NotifyPolicy(private val clock: () -> Long = System::currentTimeMillis) {
    private var startedAt: Long? = null
    private var lastExit: Int? = null
    private var lastBellAt = Long.MIN_VALUE / 2

    /** The user pressed Enter: a command may be starting. */
    fun onEnter() {
        if (startedAt == null) startedAt = clock()
    }

    fun onSignal(signal: Signal, visibility: Visibility, lastLine: String, tabTitle: String): NotificationSpec? {
        when (signal) {
            is Signal.Bell -> {
                if (visibility.visible) return null
                val now = clock()
                if (now - lastBellAt < BELL_GAP_MS) return null
                lastBellAt = now
                return NotificationSpec("$tabTitle needs attention", lastLine)
            }
            is Signal.Osc -> when (signal.code) {
                "133" -> when (signal.args.firstOrNull()) {
                    "D" -> lastExit = signal.args.getOrNull(1)?.toIntOrNull()
                    "A" -> {
                        val started = startedAt ?: return null
                        val exit = lastExit
                        startedAt = null
                        lastExit = null
                        val took = clock() - started
                        if (visibility.visible || took < MIN_COMMAND_MS) return null
                        val title = if (exit == null || exit == 0) "Finished in ${duration(took)} · $tabTitle"
                        else "Failed (exit $exit) after ${duration(took)} · $tabTitle"
                        return NotificationSpec(title, lastLine)
                    }
                }
                "9" -> {
                    if (signal.args.firstOrNull() == "4" && signal.args.size > 1) return null // progress
                    val body = signal.args.joinToString(";")
                    if (visibility.visible || body.isEmpty()) return null
                    return NotificationSpec(tabTitle, body)
                }
                "777" -> {
                    if (signal.args.firstOrNull() != "notify" || visibility.visible) return null
                    val title = signal.args.getOrNull(1)?.takeIf { it.isNotEmpty() } ?: tabTitle
                    return NotificationSpec(title, signal.args.drop(2).joinToString(";"))
                }
            }
        }
        return null
    }

    private fun duration(ms: Long): String {
        val s = ms / 1000
        return when {
            s < 60 -> "${s}s"
            s < 3600 -> "${s / 60}m ${s % 60}s"
            else -> "${s / 3600}h ${s % 3600 / 60}m"
        }
    }

    private companion object {
        const val MIN_COMMAND_MS = 10_000L
        const val BELL_GAP_MS = 30_000L
    }
}
