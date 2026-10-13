package com.aiterm.aiterm

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class OutputRingTest {
    private fun ring(cap: Int) = OutputRing(cap)
    private fun OutputRing.text() = String(snapshot())

    @Test
    fun keepsEverythingUnderCapacity() {
        val r = ring(64)
        r.append("hello\n".toByteArray())
        r.append("world\n".toByteArray())
        assertEquals("hello\nworld\n", r.text())
    }

    @Test
    fun dropsOldestAndRestartsAtALineBoundary() {
        val r = ring(16)
        r.append("aaaaaaaa\nbbbbbbb\ncc\n".toByteArray()) // 20 bytes
        // The first kept byte would be mid-line; the snapshot starts after
        // the next newline so a replay never begins inside a line or escape.
        assertEquals("bbbbbbb\ncc\n", r.text())
    }

    @Test
    fun appendsLargerThanCapacityKeepTheTail() {
        val r = ring(8)
        r.append("0123456789\nab".toByteArray())
        assertEquals("ab", r.text())
    }

    @Test
    fun noNewlineInTheWindowKeepsTheRawTail() {
        val r = ring(4)
        r.append("abcdefgh".toByteArray())
        assertArrayEquals("efgh".toByteArray(), r.snapshot())
    }

    @Test
    fun wrapsAroundRepeatedly() {
        val r = ring(10)
        repeat(100) { r.append("line$it\n".toByteArray()) }
        assertEquals("line99\n", r.text())
    }
}
