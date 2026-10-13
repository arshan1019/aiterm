package com.aiterm.aiterm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Posts "your command finished" / "Claude needs you" notifications for a
 * session, with a reply field and an Enter button that type straight into
 * that shell, so a prompt can be answered without opening the app.
 */
object SessionNotifier {
    private const val CHANNEL = "activity"
    const val EXTRA_SESSION = "session"
    const val KEY_REPLY = "reply"
    private const val ACTION_REPLY = "com.aiterm.aiterm.REPLY"
    private const val ACTION_ENTER = "com.aiterm.aiterm.ENTER"

    private fun idFor(session: Int) = 1000 + session

    fun show(context: Context, session: Int, spec: NotificationSpec) {
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Commands and prompts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "A long command finished, or a program like Claude Code needs input"
            },
        )
        val open = PendingIntent.getActivity(
            context, idFor(session),
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_SESSION, session),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        fun broadcast(action: String, mutable: Boolean) = PendingIntent.getBroadcast(
            context, idFor(session) * 4 + if (action == ACTION_REPLY) 1 else 2,
            Intent(context, ReplyReceiver::class.java).setAction(action).putExtra(EXTRA_SESSION, session),
            PendingIntent.FLAG_UPDATE_CURRENT or (if (mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE),
        )
        val reply = Notification.Action.Builder(null, "Reply", broadcast(ACTION_REPLY, mutable = true))
            .addRemoteInput(RemoteInput.Builder(KEY_REPLY).setLabel("Type and send (Enter is added)").build())
            .build()
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_terminal)
            .setContentTitle(spec.title)
            .setContentText(spec.body)
            .setStyle(Notification.BigTextStyle().bigText(spec.body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .addAction(reply)
            .addAction(Notification.Action.Builder(null, "Enter", broadcast(ACTION_ENTER, mutable = false)).build())
            .build()
        nm.notify(idFor(session), notification)
    }

    fun cancel(context: Context, session: Int) {
        context.getSystemService(NotificationManager::class.java).cancel(idFor(session))
    }

    /** Reply / Enter from a notification. */
    fun onAction(context: Context, intent: Intent) {
        val session = intent.getIntExtra(EXTRA_SESSION, -1)
        if (session < 0) return
        val text = when (intent.action) {
            ACTION_REPLY -> RemoteInput.getResultsFromIntent(intent)?.getCharSequence(KEY_REPLY)?.toString() ?: return
            ACTION_ENTER -> ""
            else -> return
        }
        SessionRegistry.write(session, "$text\r")
        cancel(context, session)
    }
}

class ReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = SessionNotifier.onAction(context, intent)
}
