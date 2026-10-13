package com.aiterm.aiterm

import org.junit.Assert.assertEquals
import org.junit.Test

class TerminalSignalsTest {
    private fun scan(vararg chunks: String): Pair<List<Signal>, TerminalSignals> {
        val s = TerminalSignals()
        val out = mutableListOf<Signal>()
        chunks.forEach { out += s.feed(it.toByteArray()) }
        return out to s
    }

    @Test
    fun bellOutsideAnEscapeIsABell() {
        assertEquals(listOf(Signal.Bell), scan("ding\u0007").first)
    }

    @Test
    fun belEndingAnOscIsNotABell() {
        assertEquals(listOf(Signal.Osc("9", listOf("Claude needs input"))), scan("\u001b]9;Claude needs input\u0007").first)
    }

    @Test
    fun oscSplitAcrossReadsAndStTerminated() {
        val (signals, _) = scan("\u001b]777;notify;Bu", "ild;done\u001b", "\\")
        assertEquals(listOf(Signal.Osc("777", listOf("notify", "Build", "done"))), signals)
    }

    @Test
    fun promptMarks() {
        val (signals, _) = scan("\u001b]133;D;1\u0007\u001b]7;file://localhost/root\u0007\u001b]133;A\u0007")
        assertEquals(
            listOf(
                Signal.Osc("133", listOf("D", "1")),
                Signal.Osc("7", listOf("file://localhost/root")),
                Signal.Osc("133", listOf("A")),
            ),
            signals,
        )
    }

    @Test
    fun lastLineIsPlainTextWithoutColours() {
        val (_, s) = scan("one\r\n\u001b[31mtwo\u001b[0m\r\n", "partial")
        assertEquals("partial", s.lastLine())
        val (_, s2) = scan("one\r\n\u001b[1;32mBuild OK\u001b[0m\r\n\r\n")
        assertEquals("Build OK", s2.lastLine())
    }

    @Test
    fun hugeOscIsDroppedNotBuffered() {
        val (signals, _) = scan("\u001b]52;c;" + "A".repeat(100_000) + "\u0007ok\u0007")
        assertEquals(listOf(Signal.Bell), signals)
    }
}
