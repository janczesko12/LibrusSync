package pl.novydev.librussync

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class UpcomingWidget : AppWidgetProvider() {
 override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
  val prefs = context.getSharedPreferences("librussync", Context.MODE_PRIVATE)
  ids.forEach { id ->
   val profile = prefs.getString("active_profile", "Janek") ?: "Janek"
   val student = prefs.getString("${profile}_name", profile) ?: profile
   val title = prefs.getString("${profile}_next_title", null)
   val timestamp = prefs.getLong("${profile}_next_date", 0L)
   val views = RemoteViews(context.packageName, R.layout.widget_upcoming)
   views.setTextViewText(R.id.widget_student, student)
   if (title.isNullOrBlank() || timestamp <= 0L) {
    views.setTextViewText(R.id.widget_subject, "Brak pobranych terminów")
    views.setTextViewText(R.id.widget_date, "Otwórz aplikację i zsynchronizuj Librusa")
   } else {
    val days = ((timestamp - System.currentTimeMillis()) / 86400000L).toInt().coerceAtLeast(0)
    val countdown = when (days) { 0 -> "Dzisiaj"; 1 -> "Jutro"; else -> "Za $days dni" }
    val date = SimpleDateFormat("d MMM", Locale("pl", "PL")).format(Date(timestamp))
    views.setTextViewText(R.id.widget_subject, title)
    views.setTextViewText(R.id.widget_date, "$countdown • $date")
   }
   val open = PendingIntent.getActivity(context, id, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
   views.setOnClickPendingIntent(R.id.widget_root, open)
   manager.updateAppWidget(id, views)
  }
 }
 companion object {
  fun refresh(context: Context) {
   val manager = AppWidgetManager.getInstance(context)
   val intent = Intent(context, UpcomingWidget::class.java).apply {
    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, manager.getAppWidgetIds(ComponentName(context, UpcomingWidget::class.java)))
   }
   context.sendBroadcast(intent)
  }
 }
}
