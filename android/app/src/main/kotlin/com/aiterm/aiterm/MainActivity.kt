package com.aiterm.aiterm

import android.Manifest
import android.content.pm.PackageManager
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
                    ),
                )
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
