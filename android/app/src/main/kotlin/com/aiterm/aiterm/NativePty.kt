package com.aiterm.aiterm

object NativePty {
    init {
        System.loadLibrary("aiterm-pty")
    }

    /** Returns [masterFd, pid]; throws IOException on failure. */
    @JvmStatic
    external fun createSubprocess(
        cwd: String,
        argv: Array<String>,
        envp: Array<String>,
        rows: Int,
        cols: Int,
    ): IntArray

    @JvmStatic
    external fun setWindowSize(fd: Int, rows: Int, cols: Int)

    @JvmStatic
    external fun waitFor(pid: Int): Int
}
