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
 override fun onReceive(context: Context, intent: Intent) {
  super.onReceive(context, intent)
  if (intent.action == ACTION_NEXT || intent.action == ACTION_PREVIOUS) {
   val prefs = context.getSharedPreferences("librussync", Context.MODE_PRIVATE)
   val current = prefs.getString("active_profile", "Janek") ?: "Janek"
   val next = if (current == "Janek") "Franek" else "Janek"
   prefs.edit().putString("active_profile", next).apply()
   refresh(context)
  }
 }

 override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
  val prefs = context.getSharedPreferences("librussync", Context.MODE_PRIVATE)
  ids.forEach { id ->
   val profile = prefs.getString("active_profile", "Janek") ?: "Janek"
   val student = prefs.getString("${profile}_name", profile)?.ifBlank { profile } ?: profile
   val title = prefs.getString("${profile}_next_title", null)
   val timestamp = prefs.getLong("${profile}_next_date", 0L)
   val views = RemoteViews(context.packageName, R.layout.widget_upcoming)
   views.setTextViewText(R.id.widget_student, student)
   val previous = PendingIntent.getBroadcast(context, id * 10 + 1, Intent(context, UpcomingWidget::class.java).setAction(ACTION_PREVIOUS), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
   val next = PendingIntent.getBroadcast(context, id * 10 + 2, Intent(context, UpcomingWidget::class.java).setAction(ACTION_NEXT), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
   views.setOnClickPendingIntent(R.id.widget_previous, previous)
   views.setOnClickPendingIntent(R.id.widget_next, next)
   if (title.isNullOrBlank() || timestamp <= 0L) {
    views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
    views.setViewVisibility(R.id.widget_events, android.view.View.GONE)
    views.setTextViewText(R.id.widget_empty, "Brak pobranych terminów • połącz Librusa w aplikacji")
   } else {
    views.setViewVisibility(R.id.widget_empty, android.view.View.GONE)
    views.setViewVisibility(R.id.widget_events, android.view.View.VISIBLE)
    val days = ((timestamp - System.currentTimeMillis()) / 86400000L).toInt().coerceAtLeast(0)
    val countdown = when (days) { 0 -> "Dzisiaj"; 1 -> "Jutro"; else -> "Za $days dni" }
    val date = SimpleDateFormat("d MMM", Locale("pl", "PL")).format(Date(timestamp))
    views.setTextViewText(R.id.widget_event_1, "• $title  |  $countdown • $date")
    views.setTextViewText(R.id.widget_event_2, "")
    views.setTextViewText(R.id.widget_event_3, "")
   }
   val open = PendingIntent.getActivity(context, id, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
   views.setOnClickPendingIntent(R.id.widget_root, open)
   manager.updateAppWidget(id, views)
  }
 }

 companion object {
  const val ACTION_NEXT = "pl.novydev.librussync.WIDGET_NEXT"
  const val ACTION_PREVIOUS = "pl.novydev.librussync.WIDGET_PREVIOUS"
  fun refresh(context: Context) {
   val manager = AppWidgetManager.getInstance(context)
   val ids = manager.getAppWidgetIds(ComponentName(context, UpcomingWidget::class.java))
   if (ids.isNotEmpty()) {
    val intent = Intent(context, UpcomingWidget::class.java).apply {
     action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
     putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
    }
    context.sendBroadcast(intent)
   }
  }
 }
}
