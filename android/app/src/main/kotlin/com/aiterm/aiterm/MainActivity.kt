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
    private var keepAlive: KeepAlivePlugin? = null
    private var ptyChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SessionRegistry.init(this)
        SshAgent.activity = java.lang.ref.WeakReference(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aiterm/ssh").setMethodCallHandler(SshPlugin())

        ptyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aiterm/pty").apply {
            setMethodCallHandler(ptyPlugin)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aiterm/pty/output",
        ).setStreamHandler(ptyPlugin)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aiterm/needle",
        ).setMethodCallHandler(NeedlePlugin())

        val keepAliveChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aiterm/keepalive")
        keepAlive = KeepAlivePlugin(this, keepAliveChannel).also { keepAliveChannel.setMethodCallHandler(it) }

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

    /** A tapped session notification: show that tab. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openSessionFrom(intent)
    }

    override fun onPostResume() {
        super.onPostResume()
        openSessionFrom(intent)
    }

    private fun openSessionFrom(intent: Intent?) {
        val id = intent?.getIntExtra(SessionNotifier.EXTRA_SESSION, -1) ?: -1
        if (id < 0) return
        intent?.removeExtra(SessionNotifier.EXTRA_SESSION)
        ptyChannel?.invokeMethod("open", mapOf("id" to id))
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            MIC_REQUEST -> {
                micResult?.success(granted)
                micResult = null
            }
            KeepAlivePlugin.NOTIFICATION_REQUEST -> keepAlive?.onNotificationPermission(granted)
        }
    }

    companion object {
        private const val MIC_REQUEST = 41
    }
}
