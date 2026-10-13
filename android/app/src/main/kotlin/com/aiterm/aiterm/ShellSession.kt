package com.aiterm.aiterm

import java.io.File
import java.io.IOException

/**
 * Runs one interactive child process.
 *
 * This is NOT a real pseudo-terminal: ProcessBuilder gives us plain pipes,
 * so there's no job control, no window-size ioctl, and curses-style full
 * screen programs will misbehave. It's enough to run Android's own shell
 * interactively. A true PTY needs a native (JNI) forkpty()/openpty()
 * implementation — see README.md "Roadmap" before building the proot/Alpine
 * backend, which will need exactly that.
 */
class ShellSession(
    private val argv: List<String>,
    private val env: Map<String, String>,
    private val cwd: String,
    private val onData: (ByteArray) -> Unit,
    private val onExit: (Int) -> Unit,
) {
    private var process: Process? = null
    private var readerThread: Thread? = null

    @Throws(IOException::class)
    fun start() {
        val builder = ProcessBuilder(argv)
        builder.directory(File(cwd))
        builder.environment().putAll(env)
        builder.redirectErrorStream(true)
        val p = builder.start()
        process = p

        readerThread = Thread {
            val buf = ByteArray(4096)
            try {
                val input = p.inputStream
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    onData(buf.copyOf(n))
                }
            } catch (_: IOException) {
                // stream closed under us when the process is killed; fine.
            }
            val code = try {
                p.waitFor()
            } catch (_: InterruptedException) {
                -1
            }
            onExit(code)
        }
        readerThread?.isDaemon = true
        readerThread?.start()
    }

    fun write(data: String) {
        try {
            process?.outputStream?.let {
                it.write(data.toByteArray(Charsets.UTF_8))
                it.flush()
            }
        } catch (_: IOException) {
            // process already gone; caller will see onExit.
        }
    }

    /** No-op until a real PTY backend exists; kept so the Dart contract is stable. */
    fun resize(rows: Int, cols: Int) {}

    fun stop() {
        process?.destroy()
        process = null
    }
}
