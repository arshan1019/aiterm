package com.aiterm.aiterm

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val ptyPlugin = PtyPlugin()
    private var micResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aiterm/pty",
        ).setMethodCallHandler(ptyPlugin)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aiterm/pty/output",
        ).setStreamHandler(ptyPlugin)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aiterm/needle",
        ).setMethodCallHandler(NeedlePlugin())

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aiterm/env",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "paths" -> result.success(
                    mapOf(
                        "nativeLibDir" to applicationInfo.nativeLibraryDir,
                        "filesDir" to filesDir.absolutePath,
                        "cacheDir" to cacheDir.absolutePath,
                        // /proc/uptime is unreadable for apps; the guest gets a stand-in.
                        "uptimeMs" to SystemClock.elapsedRealtime().toString(),
                    ),
                )
                "openUrl" -> try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url"))))
                    result.success(null)
                } catch (e: ActivityNotFoundException) {
                    result.error("no_app", "No app can open this link", null)
                }
                "requestMic" -> {
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        micResult?.success(false)
                        micResult = result
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MIC_REQUEST) {
            micResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            micResult = null
        }
    }

    companion object {
        private const val MIC_REQUEST = 41
    }
}
