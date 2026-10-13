package com.aiterm.aiterm

import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

/** One child process attached to a real pseudo-terminal (see cpp/pty_native.c). */
class ShellSession(
    private val argv: List<String>,
    private val env: Map<String, String>,
    private val cwd: String,
    private val rows: Int,
    private val cols: Int,
    private val onData: (ByteArray) -> Unit,
    private val onExit: (Int) -> Unit,
) {
    private var master: ParcelFileDescriptor? = null
    private var output: FileOutputStream? = null
    private var pid = -1

    @Throws(IOException::class)
    fun start() {
        val envp = env.map { "${it.key}=${it.value}" }.toTypedArray()
        val (fd, childPid) = NativePty.createSubprocess(cwd, argv.toTypedArray(), envp, rows, cols)
        pid = childPid
        val pfd = ParcelFileDescriptor.adoptFd(fd)
        master = pfd
        // Plain streams over the shared fd: they don't own it, so only pfd.close() closes it.
        val input = FileInputStream(pfd.fileDescriptor)
        output = FileOutputStream(pfd.fileDescriptor)

        Thread {
            val buf = ByteArray(8192)
            try {
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    onData(buf.copyOf(n))
                }
            } catch (_: IOException) {
                // EIO on the master once the child exits; expected.
            }
            onExit(NativePty.waitFor(childPid))
        }.apply { isDaemon = true }.start()
    }

    fun write(data: String) {
        try {
            output?.write(data.toByteArray(Charsets.UTF_8))
        } catch (_: IOException) {
        }
    }

    fun resize(rows: Int, cols: Int) {
        master?.let { NativePty.setWindowSize(it.fd, rows, cols) }
    }

    fun stop() {
        if (pid > 0) {
            try {
                Os.kill(pid, OsConstants.SIGHUP)
            } catch (_: Exception) {
            }
        }
        try {
            master?.close()
        } catch (_: IOException) {
        }
        master = null
    }
}
