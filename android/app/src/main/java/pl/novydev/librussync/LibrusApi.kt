package pl.novydev.librussync

import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.concurrent.TimeUnit

data class SchoolEvent(
    val id: String,
    val title: String,
    val subject: String,
    val category: String,
    val timestamp: Long,
    val endTimestamp: Long,
    val notes: String
) {
    val countdown: String
        get() {
            val zone = ZoneId.systemDefault()
            val today = Instant.now().atZone(zone).toLocalDate()
            val eventDay = Instant.ofEpochMilli(timestamp).atZone(zone).toLocalDate()
            val days = java.time.temporal.ChronoUnit.DAYS.between(today, eventDay)
            return when {
                days < 0 -> "Minęło"
                days == 0L -> "Dzisiaj"
                days == 1L -> "Jutro"
                else -> "Za $days dni"
            }
        }

    val dateLabel: String
        get() = Instant.ofEpochMilli(timestamp).atZone(ZoneId.systemDefault())
            .format(DateTimeFormatter.ofPattern("d MMM", java.util.Locale("pl", "PL")))
}

class LibrusException(message: String, cause: Throwable? = null) : Exception(message, cause)

class LibrusApi {
    private class MemoryCookieJar : CookieJar {
        private val stored = mutableListOf<Cookie>()
        @Synchronized override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
            cookies.forEach { cookie ->
                stored.removeAll { it.name == cookie.name && it.domain == cookie.domain && it.path == cookie.path }
                if (cookie.expiresAt > System.currentTimeMillis()) stored.add(cookie)
            }
            stored.removeAll { it.expiresAt <= System.currentTimeMillis() }
        }
        @Synchronized override fun loadForRequest(url: HttpUrl): List<Cookie> {
            stored.removeAll { it.expired }
            return stored.filter { it.matches(url) }
        }
        @Synchronized fun has(name: String): Boolean = stored.any { it.name == name && it.expiresAt > System.currentTimeMillis() }
    }

    private val cookieJar = MemoryCookieJar()
    private val client = OkHttpClient.Builder()
        .cookieJar(cookieJar)
        .followRedirects(false)
        .followSslRedirects(false)
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(35, TimeUnit.SECONDS)
        .callTimeout(60, TimeUnit.SECONDS)
        .build()

    private val userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
    private val portalLogin = "https://synergia.librus.pl/loguj/portalRodzina"
    private val authorizationUrl = "https://api.librus.pl/OAuth/Authorization?client_id=46"
    private val authorizationScopedUrl = "https://api.librus.pl/OAuth/Authorization?client_id=46&response_type=code&scope=mydata"
    private val gateway = "https://synergia.librus.pl/gateway/api/2.0"

    fun fetchAssessments(login: String, password: String): List<SchoolEvent> {
        if (login.isBlank() || password.isBlank()) throw LibrusException("Wpisz login i hasło do Librus Synergia.")
        login(login.trim(), password)
        val me = getJson("Me")
        val homework = getJson("HomeWorks")
        val categoriesJson = runCatching { getJson("HomeWorks/Categories") }.getOrDefault(JSONObject())
        val subjectsJson = runCatching { getJson("Subjects") }.getOrDefault(JSONObject())
        val categories = nameMap(categoriesJson, "Categories")
        val subjects = nameMap(subjectsJson, "Subjects")
        val rows = homework.optJSONArray("HomeWorks") ?: JSONArray()
        val now = System.currentTimeMillis()
        val result = mutableListOf<SchoolEvent>()
        for (index in 0 until rows.length()) {
            val row = rows.optJSONObject(index) ?: continue
            val event = mapEvent(row, categories, subjects) ?: continue
            if (event.timestamp >= now - TimeUnit.DAYS.toMillis(1) && isAssessment(event)) {
                result += event
            }
        }
        return result.distinctBy { it.id }.sortedBy { it.timestamp }
    }

    private fun login(login: String, password: String) {
        val first = request(portalLogin, "GET")
        val firstLocation = first.header("Location")
        first.close()
        if (firstLocation.isNullOrBlank()) {
            throw LibrusException("Nie udało się rozpocząć logowania do Librusa. Spróbuj ponownie później.")
        }
        val authUrl = resolve(portalLogin, firstLocation)
        request(authUrl, "GET").close()

        val form = listOf("action" to "login", "login" to login, "pass" to password)
            .joinToString("&") { "${encode(it.first)}=${encode(it.second)}" }
            .toRequestBody("application/x-www-form-urlencoded; charset=utf-8".toMediaType())
        val post = request(
            authorizationUrl,
            "POST",
            form,
            mapOf(
                "Accept" to "*/*",
                "Accept-Language" to "en-US,en;q=0.9,pl;q=0.8",
                "Cache-Control" to "no-cache",
                "Pragma" to "no-cache",
                "Origin" to "https://api.librus.pl",
                "Referer" to authorizationUrl,
                "X-Requested-With" to "XMLHttpRequest"
            )
        )
        val postCode = post.code
        val postBody = post.body?.string().orEmpty()
        post.close()
        checkCaptcha(postBody)
        if (postCode in 400..499) throw LibrusException("Librus nie zaakceptował logowania. Sprawdź login i hasło.")
        val goTo = runCatching { JSONObject(postBody).optString("goTo") }.getOrDefault("")
        if (goTo.isBlank()) throw LibrusException("Nie udało się zalogować. Sprawdź dane konta Librus.")

        var next = resolve(authorizationScopedUrl, goTo)
        var completed = false
        for (step in 0 until 10) {
            val response = request(next, "GET")
            val code = response.code
            val location = response.header("Location")
            val responseText = response.body?.string().orEmpty()
            response.close()
            checkCaptcha(responseText)
            if (code in 300..399 && !location.isNullOrBlank()) {
                next = resolve(next, location)
            } else if (code in 200..299) {
                completed = true
                break
            } else {
                throw LibrusException("Logowanie do Librusa nie zakończyło się poprawnie (HTTP $code).")
            }
        }
        if (!completed) throw LibrusException("Logowanie do Librusa przekroczyło limit przekierowań.")
        if (!cookieJar.has("oauth_token")) {
            throw LibrusException("Librus nie utworzył sesji. Zaloguj się ponownie i sprawdź, czy nie wymaga dodatkowej weryfikacji.")
        }
    }

    private fun getJson(endpoint: String): JSONObject {
        val response = request(
            "$gateway/$endpoint",
            "GET",
            extra = mapOf("Accept" to "application/json, text/plain, */*", "Referer" to "https://synergia.librus.pl/")
        )
        val code = response.code
        val contentType = response.header("Content-Type").orEmpty()
        val body = response.body?.string().orEmpty()
        response.close()
        if (code == 401 || code == 403 || code in 300..399) {
            throw LibrusException("Sesja Librusa wygasła. Otwórz aplikację i połącz konto ponownie.")
        }
        if (code !in 200..299) throw LibrusException("Librus zwrócił błąd HTTP $code.")
        val json = try { JSONObject(body) } catch (_: Exception) {
            if (contentType.contains("text/html", true) || body.contains("<html", true) || body.contains("loguj/portal", true)) {
                throw LibrusException("Sesja Librusa wygasła. Połącz konto ponownie.")
            }
            throw LibrusException("Librus zwrócił nieprawidłowe dane.")
        }
        if (json.optInt("status", 200) in listOf(401, 403)) {
            throw LibrusException("Sesja Librusa wygasła. Połącz konto ponownie.")
        }
        if (endpoint == "HomeWorks" && !json.has("HomeWorks")) {
            throw LibrusException("Librus nie udostępnił terminarza dla tego konta.")
        }
        if (endpoint == "Me" && !json.has("Me") && !json.has("User") && !json.has("Account")) {
            throw LibrusException("Nie udało się odczytać profilu konta Librus.")
        }
        return json
    }

    private fun mapEvent(row: JSONObject, categories: Map<String, String>, subjects: Map<String, String>): SchoolEvent? {
        val id = value(row.opt("Id")).ifBlank { return null }
        val rawDate = value(row.opt("Date")).ifBlank { return null }
        val dayMillis = parseDate(rawDate) ?: return null
        val categoryId = nestedId(row.opt("Category"))
        val subjectId = nestedId(row.opt("Subject"))
        val category = categories[categoryId].orEmpty()
        val subject = subjects[subjectId].orEmpty()
        val content = row.optString("Content", "").trim()
        val timeFrom = row.optString("TimeFrom", "")
        val timeMillis = parseTime(dayMillis, timeFrom)
        val hasTime = timeMillis != null
        val timestamp = timeMillis ?: dayMillis
        val titleParts = mutableListOf<String>()
        if (content.isNotBlank()) titleParts += content
        if (subject.isNotBlank() && !content.contains(subject, ignoreCase = true)) titleParts += subject
        if (titleParts.isEmpty() && category.isNotBlank()) titleParts += category
        val title = titleParts.joinToString(" • ").ifBlank { "Wydarzenie z Librusa" }
        val notes = listOf(category.takeIf { it.isNotBlank() }?.let { "Kategoria: $it" },
            subject.takeIf { it.isNotBlank() }?.let { "Przedmiot: $it" },
            content.takeIf { it.isNotBlank() }).filterNotNull().joinToString("\n")
        return SchoolEvent(
            id = id,
            title = title,
            subject = subject,
            category = category,
            timestamp = timestamp,
            endTimestamp = timestamp + if (hasTime) TimeUnit.HOURS.toMillis(1) else TimeUnit.DAYS.toMillis(1),
            notes = notes
        )
    }

    private fun isAssessment(event: SchoolEvent): Boolean {
        val text = "${event.title} ${event.category} ${event.notes}".lowercase()
            .replace('ó', 'o').replace('ł', 'l').replace('ą', 'a').replace('ę', 'e')
            .replace('ś', 's').replace('ć', 'c').replace('ż', 'z').replace('ź', 'z')
        return listOf("sprawdzian", "kartkowka", "praca klasowa", "test", "egzamin", "spr.").any { text.contains(it) }
    }

    private fun nameMap(payload: JSONObject, key: String): Map<String, String> {
        val array = payload.optJSONArray(key) ?: JSONArray()
        val output = mutableMapOf<String, String>()
        for (index in 0 until array.length()) {
            val row = array.optJSONObject(index) ?: continue
            val id = value(row.opt("Id"))
            val name = row.optString("Name").ifBlank { row.optString("ShortName") }
            if (id.isNotBlank() && name.isNotBlank()) output[id] = name
        }
        return output
    }

    private fun nestedId(value: Any?): String {
        val obj = value as? JSONObject ?: return ""
        return value(obj.opt("Id"))
    }

    private fun value(value: Any?): String = when (value) {
        null, JSONObject.NULL -> ""
        is JSONObject -> value.optString("Id", "")
        else -> value.toString()
    }

    private fun parseDate(value: String): Long? {
        val trimmed = value.trim()
        try { return Instant.parse(trimmed).toEpochMilli() } catch (_: DateTimeParseException) { }
        try { return OffsetDateTime.parse(trimmed).toInstant().toEpochMilli() } catch (_: DateTimeParseException) { }
        try {
            val local = LocalDateTime.parse(trimmed, DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss"))
            return local.atZone(ZoneId.of("Europe/Warsaw")).toInstant().toEpochMilli()
        } catch (_: Exception) { }
        return try {
            LocalDate.parse(trimmed.take(10), DateTimeFormatter.ISO_LOCAL_DATE)
                .atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        } catch (_: Exception) { null }
    }

    private fun parseTime(day: Long, rawTime: String): Long? {
        val match = Regex("^(\\d{1,2}):(\\d{2})(?::(\\d{2}))?$").find(rawTime.trim()) ?: return null
        val date = Instant.ofEpochMilli(day).atZone(ZoneId.systemDefault()).toLocalDate()
        val hour = match.groupValues[1].toIntOrNull() ?: return null
        val minute = match.groupValues[2].toIntOrNull() ?: return null
        return date.atTime(hour, minute).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
    }

    private fun request(url: String, method: String, body: okhttp3.RequestBody? = null, extra: Map<String, String> = emptyMap()): okhttp3.Response {
        val builder = Request.Builder().url(url).header("User-Agent", userAgent)
            .header("Accept-Language", "pl-PL,pl;q=0.9,en;q=0.8")
        extra.forEach { (key, value) -> builder.header(key, value) }
        when (method) {
            "POST" -> builder.post(body ?: ByteArray(0).toRequestBody())
            else -> builder.get()
        }
        return try {
            client.newCall(builder.build()).execute()
        } catch (error: Exception) {
            throw LibrusException("Nie można połączyć się z Librusem. Sprawdź internet.", error)
        }
    }

    private fun resolve(base: String, location: String): String =
        java.net.URI(base).resolve(location).toString()

    private fun checkCaptcha(body: String) {
        val text = body.lowercase()
        if (text.contains("captcha") || text.contains("g-recaptcha") || text.contains("hcaptcha")) {
            throw LibrusException("Librus wymaga dodatkowego potwierdzenia logowania. Dokończ je w oficjalnej aplikacji lub przeglądarce.")
        }
    }

    private fun encode(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())
}
