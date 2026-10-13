package com.aiterm.aiterm

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the process, and so every terminal session, alive while the app is
 * in the background or swiped away. Runs exactly while sessions exist and
 * shows how many, with Exit and an optional wake lock (keeps the CPU awake
 * for long builds with the screen off).
 */
class SessionService : Service() {
    companion object {
        private const val CHANNEL = "sessions"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_EXIT = "com.aiterm.aiterm.EXIT"
        private const val ACTION_WAKE = "com.aiterm.aiterm.WAKE"
        private const val EXTRA_COUNT = "count"

        private var running: SessionService? = null

        /** Shows, updates or ends the service for [count] sessions. */
        fun update(context: Context, count: Int) {
            val service = running
            when {
                service != null && count == 0 -> service.stopSelf()
                service != null -> service.refresh(count)
                count > 0 -> try {
                    context.startForegroundService(
                        Intent(context, SessionService::class.java).putExtra(EXTRA_COUNT, count),
                    )
                } catch (_: Exception) {
                    // Not allowed from the background (Android 12+); sessions
                    // started from the UI always get here in the foreground.
                }
            }
        }
    }

    private var count = 0
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Running sessions", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while terminal sessions keep running"
                setShowBadge(false)
            },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_EXIT -> {
                SessionRegistry.stopAll()
                return START_NOT_STICKY
            }
            ACTION_WAKE -> toggleWakeLock()
            else -> count = intent?.getIntExtra(EXTRA_COUNT, count) ?: count
        }
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, build())
        }
        // Not restarted by the system: the shells died with the process.
        return START_NOT_STICKY
    }

    fun refresh(newCount: Int) {
        count = newCount
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, build())
    }

    @SuppressLint("WakelockTimeout") // held deliberately until the user turns it off or sessions end
    private fun toggleWakeLock() {
        val held = wakeLock
        if (held != null) {
            held.release()
            wakeLock = null
        } else {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "aiterm:sessions")
                .apply { acquire() }
        }
    }

    private fun build(): Notification {
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        fun action(name: String, req: Int) = PendingIntent.getService(
            this, req, Intent(this, SessionService::class.java).setAction(name), PendingIntent.FLAG_IMMUTABLE,
        )
        val awake = wakeLock != null
        val builder = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_terminal)
            .setContentTitle(if (count == 1) "1 session running" else "$count sessions running")
            .setContentText(if (awake) "Wake lock on: keeps running with the screen off" else "Tap to open")
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .addAction(Notification.Action.Builder(null, if (awake) "Release wake lock" else "Wake lock", action(ACTION_WAKE, 1)).build())
            .addAction(Notification.Action.Builder(null, "Exit", action(ACTION_EXIT, 2)).build())
        if (Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        return builder.build()
    }

    override fun onDestroy() {
        wakeLock?.release()
        wakeLock = null
        running = null
        super.onDestroy()
    }
}
