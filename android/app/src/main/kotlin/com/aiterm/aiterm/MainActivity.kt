package com.aiterm.aiterm

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.SystemClock
import android.provider.Settings
import android.view.HapticFeedbackConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val ptyPlugin = PtyPlugin()
    private var micResult: MethodChannel.Result? = null
    private var keepAlive: KeepAlivePlugin? = null
    private var ptyChannel: MethodChannel? = null
    private var backup: BackupPlugin? = null
    private var phoneFiles: PhoneFilesPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SessionRegistry.init(this)
        SshAgent.activity = java.lang.ref.WeakReference(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aiterm/ssh").setMethodCallHandler(SshPlugin())
        backup = BackupPlugin(this).also {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aiterm/backup").setMethodCallHandler(it)
        }

        val phoneChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aiterm/phone")
        phoneFiles = PhoneFilesPlugin(this, phoneChannel).also {
            phoneChannel.setMethodCallHandler(it)
            it.onShareIntent(intent)
        }

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

        // Haptics with Android's own feedback constants (they follow the
        // system's touch-feedback setting), newer ones falling back.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aiterm/haptics").setMethodCallHandler { call, result ->
            val sdk = Build.VERSION.SDK_INT
            val constant = when (call.method) {
                "confirm" -> if (sdk >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
                "reject" -> if (sdk >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS
                "toggleOn" -> if (sdk >= 34) HapticFeedbackConstants.TOGGLE_ON else HapticFeedbackConstants.CLOCK_TICK
                "toggleOff" -> if (sdk >= 34) HapticFeedbackConstants.TOGGLE_OFF else HapticFeedbackConstants.CLOCK_TICK
                "tick" -> if (sdk >= 34) HapticFeedbackConstants.SEGMENT_TICK else HapticFeedbackConstants.CLOCK_TICK
                "longPress" -> HapticFeedbackConstants.LONG_PRESS
                else -> null
            }
            if (constant == null) {
                result.notImplemented()
            } else {
                window.decorView.performHapticFeedback(constant)
                result.success(null)
            }
        }

        // The wallpaper's accent (Android 12+ dynamic color), for "Wallpaper colors".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aiterm/colors").setMethodCallHandler { call, result ->
            if (call.method != "accent") {
                result.notImplemented()
            } else if (Build.VERSION.SDK_INT >= 31) {
                result.success(getColor(android.R.color.system_accent1_500))
            } else {
                result.success(null)
            }
        }

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
                        // Wall-clock boot moment, the same for every session (Linux's btime).
                        "bootTimeMs" to (System.currentTimeMillis() - SystemClock.elapsedRealtime()).toString(),
                    ),
                )
                "openUrl" -> try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url"))))
                    result.success(null)
                } catch (e: ActivityNotFoundException) {
                    result.error("no_app", "No app can open this link", null)
                }
                // Phone storage in Files (copy/move between Linux and the phone).
                "storageAccess" -> result.success(hasStorageAccess())
                "requestStorageAccess" -> {
                    if (Build.VERSION.SDK_INT >= 30) {
                        val perApp = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName"))
                        try {
                            startActivity(perApp)
                        } catch (e: ActivityNotFoundException) {
                            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                        }
                    } else {
                        requestPermissions(
                            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE),
                            STORAGE_REQUEST,
                        )
                    }
                    result.success(null)
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

    @Deprecated("Needed for the document picker results")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (backup?.onActivityResult(requestCode, resultCode, data) == true) return
        phoneFiles?.onActivityResult(requestCode, resultCode, data)
    }

    /** A tapped session notification: show that tab. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Files shared to aiterm while it's running.
        if (phoneFiles?.onShareIntent(intent) == true) return
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

    private fun hasStorageAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= 30) Environment.isExternalStorageManager()
        else checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    companion object {
        private const val STORAGE_REQUEST = 43
        private const val MIC_REQUEST = 41
    }
}
