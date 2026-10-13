package com.aiterm.aiterm

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val ptyPlugin = PtyPlugin()

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
                else -> result.notImplemented()
            }
        }
    }
}
