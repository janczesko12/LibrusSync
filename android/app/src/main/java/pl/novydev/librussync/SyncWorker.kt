package pl.novydev.librussync

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        if (SyncEngine.syncAll(applicationContext)) Result.success() else Result.retry()
    } catch (_: Exception) { Result.retry() }
}

class ReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val profile = inputData.getString("profile") ?: return Result.failure()
        val eventId = inputData.getString("event_id") ?: return Result.failure()
        val timestamp = inputData.getLong("timestamp", 0L)
        val event = AgendaStore.allEvents(applicationContext, profile).firstOrNull { it.id == eventId && it.timestamp == timestamp }
        if (event != null) Notifications.show(applicationContext,
            "Nadchodząca praca • ${AgendaStore.profileName(applicationContext, profile)}",
            "${event.title} • ${AgendaStore.profileName(applicationContext, profile)}", (profile + eventId + "reminder").hashCode())
        return Result.success()
    }
}

object SyncScheduler {
    fun schedulePeriodic(context: Context) {
        val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        val request = PeriodicWorkRequestBuilder<SyncWorker>(6, TimeUnit.HOURS).setConstraints(constraints).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork("librussync_periodic_sync", ExistingPeriodicWorkPolicy.KEEP, request)
    }
    fun runNow(context: Context) {
        val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        val request = OneTimeWorkRequestBuilder<SyncWorker>().setConstraints(constraints).build()
        WorkManager.getInstance(context).enqueue(request)
    }
}
