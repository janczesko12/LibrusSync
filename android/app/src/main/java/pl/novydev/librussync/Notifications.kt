package pl.novydev.librussync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object Notifications {
    private const val CHANNEL_ID = "librussync_assessments"
    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Sprawdziany i kartkówki", NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = "Przypomnienia o najbliższych pracach z Librusa" }
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
    fun show(context: Context, title: String, text: String, id: Int) {
        ensureChannel(context)
        val open = PendingIntent.getActivity(context,id,Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(title).setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text)).setContentIntent(open).setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT).build()
        runCatching { NotificationManagerCompat.from(context).notify(id, notification) }
    }
}
