package com.aiterm.aiterm

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.net.NetworkInterface

/**
 * "aiterm/keepalive": what keeps sessions alive (battery, notifications,
 * the Android 12+ child-process limit) and the Wireless debugging pairing
 * that lifts that limit without a computer.
 *
 * Pairing: discover the pairing and connect ports over mDNS, and take the
 * 6-digit code through a notification reply so the user can stay on the
 * Wireless debugging screen (leaving it cancels the code). Dart then runs
 * adb inside Linux and reports back with "pairingResult".
 */
class KeepAlivePlugin(private val activity: Activity, private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {

    companion object {
        private const val PAIR_CHANNEL = "pairing"
        private const val PAIR_NOTIFICATION = 2
        const val KEY_CODE = "code"
        const val NOTIFICATION_REQUEST = 42

        /** Set while a pairing is in progress, for [PairingReceiver]. */
        var active: KeepAlivePlugin? = null
    }

    private val main = Handler(Looper.getMainLooper())
    private val nsd = activity.getSystemService(NsdManager::class.java)
    private val listeners = mutableListOf<NsdManager.DiscoveryListener>()
    private val pairing = mutableListOf<Found>()
    private val connect = mutableListOf<Found>()
    private var notificationsResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "requestBattery" -> {
                activity.startActivity(
                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${activity.packageName}")),
                )
                result.success(null)
            }
            "requestNotifications" -> requestNotifications(result)
            "openDeveloperOptions" -> {
                val enabled = Settings.Global.getInt(activity.contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1
                activity.startActivity(
                    Intent(if (enabled) Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS else Settings.ACTION_DEVICE_INFO_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(enabled)
            }
            "startPairing" -> {
                startPairing()
                result.success(null)
            }
            "pairingResult" -> {
                showPairing(call.argument<String>("message") ?: "", done = true)
                stopDiscovery()
                result.success(null)
            }
            "stopPairing" -> {
                stopDiscovery()
                activity.getSystemService(NotificationManager::class.java).cancel(PAIR_NOTIFICATION)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun status(): Map<String, Any> {
        val sdk = Build.VERSION.SDK_INT
        val battery = activity.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(activity.packageName)
        val notifications = Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val limit = when {
            sdk < 31 -> "na"
            else -> when (Settings.Global.getString(activity.contentResolver, "settings_enable_monitor_phantom_procs")) {
                "false" -> "disabled"
                "true" -> "enforced"
                else -> "unknown"
            }
        }
        return mapOf("sdk" to sdk, "battery" to battery, "notifications" to notifications, "childLimit" to limit)
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        notificationsResult = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    /** From MainActivity.onRequestPermissionsResult. */
    fun onNotificationPermission(granted: Boolean) {
        notificationsResult?.success(granted)
        notificationsResult = null
    }

    // ── Pairing ──────────────────────────────────────────────────────────

    private fun startPairing() {
        stopDiscovery()
        active = this
        pairing.clear()
        connect.clear()
        discover("_adb-tls-pairing._tcp", pairing)
        discover("_adb-tls-connect._tcp", connect)
        showPairing("In Wireless debugging, tap “Pair device with pairing code”, then type the code here.", done = false)
    }

    private fun discover(type: String, into: MutableList<Found>) {
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                nsd.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onServiceResolved(resolved: NsdServiceInfo) {
                        @Suppress("DEPRECATION")
                        val found = Found(resolved.host, resolved.port)
                        main.post { if (found !in into) into.add(found) }
                    }

                    override fun onResolveFailed(info: NsdServiceInfo, error: Int) {}
                })
            }

            override fun onServiceLost(info: NsdServiceInfo) {}
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, error: Int) {}
            override fun onStopDiscoveryFailed(type: String, error: Int) {}
        }
        listeners += listener
        nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    private fun stopDiscovery() {
        listeners.forEach { runCatching { nsd.stopServiceDiscovery(it) } }
        listeners.clear()
        if (active === this) active = null
    }

    /** A code typed into the notification ([PairingReceiver]). */
    fun onCode(code: String) {
        val own = ownAddresses()
        val pairPort = pickOwnPort(pairing, own)
        val connectPort = pickOwnPort(connect, own)
        if (pairPort == null || connectPort == null) {
            showPairing(
                "Couldn't find Wireless debugging on this phone. Keep the pairing code on screen and try again.",
                done = false,
            )
            return
        }
        showPairing("Pairing…", done = false, progress = true)
        channel.invokeMethod("pairingCode", mapOf("code" to code.trim(), "pairPort" to pairPort, "connectPort" to connectPort))
    }

    private fun ownAddresses(): Set<InetAddress> = buildSet {
        add(InetAddress.getLoopbackAddress())
        runCatching {
            NetworkInterface.getNetworkInterfaces()?.toList()?.forEach { addAll(it.inetAddresses.toList()) }
        }
    }

    private fun showPairing(text: String, done: Boolean, progress: Boolean = false) {
        val nm = activity.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(PAIR_CHANNEL, "Wireless debugging setup", NotificationManager.IMPORTANCE_HIGH),
        )
        val builder = Notification.Builder(activity, PAIR_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_terminal)
            .setContentTitle(if (done) "Child process limit" else "Pair with aiterm")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setOnlyAlertOnce(true)
            .setAutoCancel(done)
        if (progress) builder.setProgress(0, 0, true)
        if (!done && !progress) {
            val reply = PendingIntent.getBroadcast(
                activity, 0,
                Intent(activity, PairingReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            val input = RemoteInput.Builder(KEY_CODE).setLabel("6-digit pairing code").build()
            builder.addAction(Notification.Action.Builder(null, "Enter code", reply).addRemoteInput(input).build())
        }
        nm.notify(PAIR_NOTIFICATION, builder.build())
    }
}

/** Receives the pairing code typed into the notification. */
class PairingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val code = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(KeepAlivePlugin.KEY_CODE)?.toString()
        if (code != null) KeepAlivePlugin.active?.onCode(code)
    }
}
