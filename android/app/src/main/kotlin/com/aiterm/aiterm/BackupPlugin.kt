package com.aiterm.aiterm

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread
import kotlin.system.exitProcess

/**
 * "aiterm/backup": the system file picker (so a backup can go to local
 * storage, Google Drive or anywhere a documents provider offers) and
 * streaming Android's tar straight to or from the chosen document.
 */
class BackupPlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val SAVE_REQUEST = 51
        const val OPEN_REQUEST = 52
    }

    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var pendingCall: MethodCall? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "save" -> pick(call, result, SAVE_REQUEST) {
                Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("application/gzip")
                    .putExtra(Intent.EXTRA_TITLE, call.argument<String>("fileName"))
            }
            "open" -> pick(call, result, OPEN_REQUEST) {
                Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
            }
            "stopAll" -> {
                SessionRegistry.stopAll()
                // Give the shells a moment to exit before files move under them.
                main.postDelayed({ result.success(null) }, 700)
            }
            "restart" -> {
                val launch = activity.packageManager.getLaunchIntentForPackage(activity.packageName)!!
                activity.startActivity(Intent.makeRestartActivityTask(launch.component))
                exitProcess(0)
            }
            else -> result.notImplemented()
        }
    }

    private fun pick(call: MethodCall, result: MethodChannel.Result, request: Int, intent: () -> Intent) {
        pending?.error("busy", "Another backup is in progress", null)
        pending = result
        pendingCall = call
        activity.startActivityForResult(intent(), request)
    }

    /** From MainActivity.onActivityResult. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SAVE_REQUEST && requestCode != OPEN_REQUEST) return false
        val result = pending ?: return true
        val call = pendingCall!!
        pending = null
        pendingCall = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(if (requestCode == SAVE_REQUEST) null else false)
            return true
        }
        thread(name = "backup") {
            try {
                val value: Any = if (requestCode == SAVE_REQUEST) save(call, uri) else open(call, uri)
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("backup", e.message, null) }
            }
        }
        return true
    }

    private fun save(call: MethodCall, uri: Uri): Long {
        val args = call.argument<List<String>>("args")!!
        val process = ProcessBuilder(listOf("/system/bin/tar") + args)
            .directory(File(call.argument<String>("dir")!!))
            .redirectError(ProcessBuilder.Redirect.PIPE)
            .start()
        val errors = StringBuilder()
        val errThread = thread { errors.append(process.errorStream.bufferedReader().readText()) }
        var total = 0L
        activity.contentResolver.openOutputStream(uri, "wt")!!.use { out ->
            val buf = ByteArray(256 * 1024)
            process.inputStream.use { input ->
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    total += n
                }
            }
        }
        errThread.join()
        val code = process.waitFor()
        // tar exits 1 when a file changed while it read it; the archive is still fine.
        if (code > 1) throw IllegalStateException("tar failed ($code): ${errors.toString().trim().lines().lastOrNull()}")
        return total
    }

    private fun open(call: MethodCall, uri: Uri): Boolean {
        val staging = File(call.argument<String>("staging")!!).apply { mkdirs() }
        val process = ProcessBuilder("/system/bin/tar", "-xzf", "-", "-C", staging.absolutePath)
            .redirectError(ProcessBuilder.Redirect.PIPE)
            .start()
        val errors = StringBuilder()
        val errThread = thread { errors.append(process.errorStream.bufferedReader().readText()) }
        activity.contentResolver.openInputStream(uri)!!.use { input ->
            process.outputStream.use { input.copyTo(it, 256 * 1024) }
        }
        errThread.join()
        val code = process.waitFor()
        if (code != 0) throw IllegalStateException("Couldn't unpack the backup: ${errors.toString().trim().lines().lastOrNull()}")
        return true
    }
}
