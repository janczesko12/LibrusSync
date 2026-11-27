package pl.novydev.librussync

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

class UpcomingWidget : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_NEXT || intent.action == ACTION_PREVIOUS) {
            val prefs = context.getSharedPreferences("librussync", Context.MODE_PRIVATE)
            val current = prefs.getString("active_profile", "janek") ?: "janek"
            val next = if (current == "janek") "franek" else "janek"
            prefs.edit().putString("active_profile", next).apply()
            refresh(context)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateOne(context, manager, it, manager.getAppWidgetOptions(it)) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        updateOne(context, manager, appWidgetId, newOptions)
    }

    private fun updateOne(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        val widgetPrefs = context.getSharedPreferences("librussync", Context.MODE_PRIVATE)
        val profile = widgetPrefs.getString("active_profile", "janek") ?: "janek"
        val events = AgendaStore.allEvents(context, profile).filter { it.timestamp > System.currentTimeMillis() - 60_000 }
        val views = RemoteViews(context.packageName, R.layout.widget_upcoming)
        views.setTextViewText(R.id.widget_student, AgendaStore.profileName(context, profile))

        val previous = PendingIntent.getBroadcast(context, id * 10 + 1,
            Intent(context, UpcomingWidget::class.java).setAction(ACTION_PREVIOUS),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val next = PendingIntent.getBroadcast(context, id * 10 + 2,
            Intent(context, UpcomingWidget::class.java).setAction(ACTION_NEXT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.widget_previous, previous)
        views.setOnClickPendingIntent(R.id.widget_next, next)

        val rowIds = listOf(R.id.widget_event_1, R.id.widget_event_2, R.id.widget_event_3)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
        val visibleRows = when {
            minHeight >= 190 -> 3
            minHeight >= 135 -> 2
            else -> 1
        }
        if (events.isEmpty()) {
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            views.setTextViewText(R.id.widget_empty, "Brak pobranych prac • połącz konto Librus")
            views.setViewVisibility(R.id.widget_events, View.GONE)
        } else {
            views.setViewVisibility(R.id.widget_empty, View.GONE)
            views.setViewVisibility(R.id.widget_events, View.VISIBLE)
            rowIds.forEachIndexed { index, viewId ->
                val event = events.getOrNull(index)
                if (event != null && index < visibleRows) {
                    val label = event.subject.ifBlank { event.category.ifBlank { event.title } }
                    views.setTextViewText(viewId, "$label — ${event.countdown} • ${event.dateLabel}")
                    views.setViewVisibility(viewId, View.VISIBLE)
                } else {
                    views.setTextViewText(viewId, "")
                    views.setViewVisibility(viewId, View.GONE)
                }
            }
        }
        val open = PendingIntent.getActivity(context, id,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.widget_root, open)
        manager.updateAppWidget(id, views)
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
