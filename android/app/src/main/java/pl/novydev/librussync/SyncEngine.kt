package pl.novydev.librussync

import android.content.Context
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

object SyncEngine {
    fun syncProfile(context: Context, profile: String): ResultSummary {
        val login = AgendaStore.login(context, profile) ?: return ResultSummary(false, "Brak loginu dla ${AgendaStore.profileName(context, profile)}", 0)
        val password = AgendaStore.password(context, profile) ?: return ResultSummary(false, "Brak hasła do konta", 0)
        return try {
            val events = LibrusApi().fetchAssessments(login, password)
            val changed = AgendaStore.saveEvents(context, profile, events)
            val name = AgendaStore.profileName(context, profile)
            changed.take(5).forEach { event ->
                Notifications.show(context, "Nowa lub zmieniona praca • $name",
                    "${event.title} • ${event.countdown} • ${event.dateLabel}", (profile + event.id).hashCode())
            }
            ReminderScheduler.schedule(context, profile, events)
            AgendaStore.markSyncError(context, profile, "")
            UpcomingWidget.refresh(context)
            ResultSummary(true, "Zsynchronizowano ${events.size} prac", events.size)
        } catch (error: Exception) {
            val message = error.message ?: "Nieznany błąd synchronizacji"
            AgendaStore.markSyncError(context, profile, message)
            ResultSummary(false, message, 0)
        }
    }
    fun syncAll(context: Context): Boolean {
        val connected = listOf("janek", "franek").filter { AgendaStore.isConnected(context, it) }
        if (connected.isEmpty()) return false
        var success = false
        connected.forEach { if (syncProfile(context, it).success) success = true }
        return success
    }
}

data class ResultSummary(val success: Boolean, val message: String, val count: Int)

object ReminderScheduler {
    fun schedule(context: Context, profile: String, events: List<SchoolEvent>) {
        val workManager = WorkManager.getInstance(context)
        val reminderTag = "reminders_$profile"
        workManager.cancelAllWorkByTag(reminderTag)
        events.forEach { event ->
            val now = System.currentTimeMillis()
            val dayBefore = event.timestamp - TimeUnit.HOURS.toMillis(24)
            val hourBefore = event.timestamp - TimeUnit.HOURS.toMillis(1)
            val trigger = if (dayBefore > now + 60_000) dayBefore else hourBefore
            if (trigger <= now || event.timestamp <= now) return@forEach
            val data = Data.Builder().putString("profile", profile).putString("event_id", event.id)
                .putString("title", event.title).putLong("timestamp", event.timestamp).build()
            val request = OneTimeWorkRequestBuilder<ReminderWorker>().setInputData(data)
                .addTag(reminderTag).setInitialDelay(trigger - now, TimeUnit.MILLISECONDS).build()
            workManager.enqueueUniqueWork("reminder_${profile}_${event.id.hashCode()}", ExistingWorkPolicy.REPLACE, request)
        }
    }
}
