package com.aiterm.aiterm

/**
 * The last [capacity] bytes of a session's output, so a recreated UI can
 * redraw the terminal (see [SessionRegistry.attach]).
 *
 * When older output has been dropped, [snapshot] starts after the first
 * newline in the window, so a replay never begins inside a line or an
 * escape sequence.
 */
class OutputRing(private val capacity: Int) {
    // One spare byte remembers what preceded the window.
    private val buf = ByteArray(capacity + 1)
    private var start = 0
    private var size = 0
    private var dropped = false

    @Synchronized
    fun append(data: ByteArray) {
        var from = 0
        if (data.size > buf.size) {
            from = data.size - buf.size
            dropped = true
        }
        for (i in from until data.size) {
            val end = (start + size) % buf.size
            buf[end] = data[i]
            if (size < buf.size) size++ else {
                start = (start + 1) % buf.size
                dropped = true
            }
        }
    }

    @Synchronized
    fun snapshot(): ByteArray {
        val all = ByteArray(size) { buf[(start + it) % buf.size] }
        if (!dropped && size <= capacity) return all
        // The window is the last `capacity` bytes; `before` is the byte ahead of it.
        val windowStart = maxOf(0, all.size - capacity)
        val before = if (windowStart > 0) all[windowStart - 1] else null
        if (before == '\n'.code.toByte()) return all.copyOfRange(windowStart, all.size)
        for (i in windowStart until all.size) {
            if (all[i] == '\n'.code.toByte()) return all.copyOfRange(i + 1, all.size)
        }
        return all.copyOfRange(windowStart, all.size)
    }
}
