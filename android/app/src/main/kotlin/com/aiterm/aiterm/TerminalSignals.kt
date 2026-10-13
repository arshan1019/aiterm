package com.aiterm.aiterm

import java.io.ByteArrayOutputStream

/** Something in a session's output worth acting on. */
sealed class Signal {
    object Bell : Signal() {
        override fun toString() = "Bell"
    }

    /** An OSC sequence: `ESC ] code ; args… (BEL | ESC \)`. */
    data class Osc(val code: String, val args: List<String>) : Signal()
}

/**
 * Scans raw terminal output, natively, for bells and OSC sequences (shell
 * integration and program notifications), and remembers the last line of
 * text. Runs even with no UI attached, so notifications work after the app
 * is swiped away. Sequences may be split across reads.
 */
class TerminalSignals {
    private enum class State { TEXT, ESC, CSI, OSC, OSC_ESC }

    private var state = State.TEXT
    private val osc = ByteArrayOutputStream()
    private var oscOverflow = false
    private val line = ByteArrayOutputStream()
    private var lastFull = ""

    fun feed(data: ByteArray): List<Signal> {
        val out = mutableListOf<Signal>()
        for (b in data) {
            val c = b.toInt() and 0xFF
            when (state) {
                State.TEXT -> when (c) {
                    0x07 -> out += Signal.Bell
                    0x1B -> state = State.ESC
                    0x0A -> commitLine()
                    0x0D -> {}
                    else -> if (c >= 0x20 && line.size() < MAX_LINE) line.write(c)
                }
                State.ESC -> state = when (c) {
                    ']'.code -> State.OSC.also { osc.reset(); oscOverflow = false }
                    '['.code -> State.CSI
                    else -> State.TEXT
                }
                State.CSI -> if (c in 0x40..0x7E) state = State.TEXT
                State.OSC -> when (c) {
                    0x07 -> { emitOsc(out); state = State.TEXT }
                    0x1B -> state = State.OSC_ESC
                    else -> if (osc.size() < MAX_OSC) osc.write(c) else oscOverflow = true
                }
                State.OSC_ESC -> { emitOsc(out); state = State.TEXT }
            }
        }
        return out
    }

    /** The last non-blank line of plain text (the current one if started). */
    fun lastLine(): String {
        val current = line.toString(Charsets.UTF_8.name()).trim()
        return current.ifEmpty { lastFull }
    }

    private fun commitLine() {
        val text = line.toString(Charsets.UTF_8.name()).trim()
        if (text.isNotEmpty()) lastFull = text
        line.reset()
    }

    private fun emitOsc(out: MutableList<Signal>) {
        if (oscOverflow) return // e.g. a huge clipboard (OSC 52) payload
        val parts = osc.toString(Charsets.UTF_8.name()).split(';')
        out += Signal.Osc(parts.first(), parts.drop(1))
    }

    private companion object {
        const val MAX_OSC = 4096
        const val MAX_LINE = 500
    }
}
