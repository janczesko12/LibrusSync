package pl.novydev.librussync

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

object AgendaStore {
    private const val PREFS = "librussync_data"
    private val gson = Gson()
    fun allEvents(context: Context, profile: String): List<SchoolEvent> {
        val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("events_$profile", null) ?: return emptyList()
        return runCatching { gson.fromJson<List<SchoolEvent>>(json, object : TypeToken<List<SchoolEvent>>() {}.type) ?: emptyList() }
            .getOrDefault(emptyList()).filter { it.isUpcoming }.sortedBy { it.timestamp }
    }
    fun saveEvents(context: Context, profile: String, events: List<SchoolEvent>): List<SchoolEvent> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val previous = allEvents(context, profile)
        val firstSync = !prefs.getBoolean("has_sync_$profile", false)
        val oldById = previous.associateBy { it.id }
        val changed = events.filter { event -> oldById[event.id]?.let { fingerprint(it) != fingerprint(event) } ?: true }
        prefs.edit().putString("events_$profile", gson.toJson(events))
            .putBoolean("has_sync_$profile", true).putLong("last_sync_$profile", System.currentTimeMillis()).apply()
        return if (firstSync) emptyList() else changed
    }
    fun hasCompletedSync(context: Context, profile: String) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("has_sync_$profile", false)
    fun lastSync(context: Context, profile: String) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong("last_sync_$profile", 0L)
    fun profileName(context: Context, profile: String): String {
        val default = if (profile == "janek") "Janek" else "Franek"
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("name_$profile", default)?.ifBlank { default } ?: default
    }
    fun setProfileName(context: Context, profile: String, name: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("name_$profile", name.trim()).apply()
    }
    fun login(context: Context, profile: String) = SecurePrefs.get(context, "login_$profile")
    fun password(context: Context, profile: String) = SecurePrefs.get(context, "password_$profile")
    fun saveCredentials(context: Context, profile: String, login: String, password: String) {
        SecurePrefs.put(context, "login_$profile", login.trim())
        SecurePrefs.put(context, "password_$profile", password)
    }
    fun clearCredentials(context: Context, profile: String) {
        SecurePrefs.delete(context, "login_$profile")
        SecurePrefs.delete(context, "password_$profile")
    }
    fun clearProfileData(context: Context, profile: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove("events_$profile").remove("has_sync_$profile")
            .remove("last_sync_$profile").remove("error_$profile").apply()
    }
    fun isConnected(context: Context, profile: String) = !login(context, profile).isNullOrBlank() && !password(context, profile).isNullOrBlank()
    fun markSyncError(context: Context, profile: String, message: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("error_$profile", message).apply()
    }
    fun lastError(context: Context, profile: String) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("error_$profile", null)
    private fun fingerprint(event: SchoolEvent) = listOf(event.title,event.subject,event.category,event.timestamp.toString(),event.endTimestamp.toString(),event.notes).joinToString("|")
}
