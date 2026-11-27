package pl.novydev.librussync

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val Navy = Color(0xFF10111F)
private val Panel = Color(0xFF1B1D30)
private val Purple = Color(0xFF9B7BFF)
private val Muted = Color(0xFFB8B8C8)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Notifications.ensureChannel(this)
        setContent { LibrusSyncApp(this) }
    }
}

@Composable
private fun LibrusSyncApp(context: Context) {
    val scope = rememberCoroutineScope()
    val prefs = remember { context.getSharedPreferences("librussync", Context.MODE_PRIVATE) }
    val storedProfile = prefs.getString("active_profile", "janek") ?: "janek"
    var profile by remember { mutableStateOf(if (storedProfile.equals("Franek", true)) "franek" else "janek") }
    var name by remember { mutableStateOf(AgendaStore.profileName(context, profile)) }
    var login by remember { mutableStateOf(AgendaStore.login(context, profile).orEmpty()) }
    var password by remember { mutableStateOf("") }
    var events by remember { mutableStateOf(AgendaStore.allEvents(context, profile)) }
    var status by remember { mutableStateOf(AgendaStore.lastError(context, profile)?.takeIf { it.isNotBlank() } ?: "Połącz konto Librus Synergia") }
    var busy by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        prefs.edit().putString("active_profile", profile).apply()
        SyncScheduler.schedulePeriodic(context)
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (AgendaStore.isConnected(context, "janek") || AgendaStore.isConnected(context, "franek")) {
            SyncScheduler.runNow(context)
        }
    }
    LaunchedEffect(profile) {
        name = AgendaStore.profileName(context, profile)
        login = AgendaStore.login(context, profile).orEmpty()
        password = ""
        events = AgendaStore.allEvents(context, profile)
        status = AgendaStore.lastError(context, profile)?.takeIf { it.isNotBlank() }
            ?: if (AgendaStore.isConnected(context, profile)) "Konto zapisane • gotowe do synchronizacji" else "Połącz konto Librus Synergia"
        UpcomingWidget.refresh(context)
        while (true) {
            delay(30_000)
            events = AgendaStore.allEvents(context, profile)
        }
    }

    val isDark = isSystemInDarkTheme()
    val appColors = if (isDark) darkColorScheme(
        primary = Purple, background = Color(0xFF10111F), surface = Color(0xFF1B1D30),
        onBackground = Color(0xFFF7F6FC), onSurface = Color(0xFFF7F6FC),
        onPrimary = Color(0xFF171327), surfaceVariant = Color(0xFF292A40),
        onSurfaceVariant = Color(0xFFB8B8C8), outline = Color(0xFF514D68)
    ) else lightColorScheme(
        primary = Color(0xFF6650A4), background = Color(0xFFF7F7FB), surface = Color.White,
        onBackground = Color(0xFF191825), onSurface = Color(0xFF191825),
        onPrimary = Color.White, surfaceVariant = Color(0xFFECEAF4),
        onSurfaceVariant = Color(0xFF625F70), outline = Color(0xFFD5D1E0)
    )
    MaterialTheme(
        colorScheme = appColors,
        shapes = Shapes(
            extraSmall = RoundedCornerShape(10.dp),
            small = RoundedCornerShape(14.dp),
            medium = RoundedCornerShape(20.dp),
            large = RoundedCornerShape(26.dp),
            extraLarge = RoundedCornerShape(30.dp)
        )
    ) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("LibrusSync", fontSize = 28.sp, color = MaterialTheme.colorScheme.onBackground)
                        Text("Sprawdziany i kartkówki • Android", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                    }
                    Surface(color = MaterialTheme.colorScheme.surfaceVariant, shape = RoundedCornerShape(50)) {
                        Text("1.0.1", Modifier.padding(horizontal = 12.dp, vertical = 7.dp), color = Purple, fontSize = 12.sp)
                    }
                }

                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ProfileButton("Janek", profile == "janek", Modifier.weight(1f)) { switchProfile("janek", prefs) { profile = it } }
                    ProfileButton("Franek", profile == "franek", Modifier.weight(1f)) { switchProfile("franek", prefs) { profile = it } }
                }
                OutlinedButton(
                    enabled = !busy && (AgendaStore.isConnected(context, "janek") || AgendaStore.isConnected(context, "franek")),
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        scope.launch {
                            busy = true
                            status = "Synchronizuję oba konta…"
                            try {
                                val success = withContext(Dispatchers.IO) { SyncEngine.syncAll(context) }
                                events = AgendaStore.allEvents(context, profile)
                                status = if (success) "Zakończono synchronizację wszystkich podłączonych kont." else "Co najmniej jedno konto nie zostało zsynchronizowane. Sprawdź status profilu."
                            } catch (error: Exception) {
                                status = friendlyError(error)
                            } finally { busy = false }
                        }
                    }
                ) { Text("Synchronizuj Janka i Franka") }

                Card(modifier = Modifier.animateContentSize(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), shape = RoundedCornerShape(26.dp)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("NAJBLIŻSZE PRACE", color = MaterialTheme.colorScheme.primary, fontSize = 11.sp)
                        Text(name.ifBlank { if (profile == "janek") "Janek" else "Franek" }, fontSize = 22.sp)
                        AnimatedContent(targetState = events, label = "assessment-list") { visibleEvents ->
                            if (visibleEvents.isEmpty()) {
                                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text("Nie ma jeszcze pobranych sprawdzianów ani kartkówek.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text("Połącz konto Librus, aby pobrać terminy.", color = Muted, fontSize = 12.sp)
                                }
                            } else {
                                Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                    visibleEvents.take(5).forEach { event ->
                                        EventRow(event)
                                    }
                                    if (visibleEvents.size > 5) {
                                        Text("i jeszcze ${visibleEvents.size - 5} kolejnych…", color = Muted, fontSize = 12.sp)
                                    }
                                }
                            }
                        }
                    }
                }

                Card(modifier = Modifier.animateContentSize(), colors = CardDefaults.cardColors(containerColor = Panel), shape = RoundedCornerShape(26.dp)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                        Text("KONTO LIBRUS", color = MaterialTheme.colorScheme.primary, fontSize = 11.sp)
                        OutlinedTextField(
                            value = name,
                            onValueChange = { name = it; AgendaStore.setProfileName(context, profile, it); UpcomingWidget.refresh(context) },
                            modifier = Modifier.fillMaxWidth(), singleLine = true, label = { Text("Nazwa profilu") }
                        )
                        OutlinedTextField(
                            value = login, onValueChange = { login = it }, modifier = Modifier.fillMaxWidth(),
                            singleLine = true, label = { Text("Login Librus") }
                        )
                        OutlinedTextField(
                            value = password, onValueChange = { password = it }, modifier = Modifier.fillMaxWidth(),
                            singleLine = true, label = { Text("Hasło Librus") },
                            visualTransformation = PasswordVisualTransformation()
                        )
                        Text(
                            if (AgendaStore.isConnected(context, profile)) "Dane konta są zapisane w Android Keystore." else "Dane logowania będą zaszyfrowane na tym urządzeniu.",
                            color = Muted, fontSize = 11.sp
                        )
                        Button(
                            enabled = !busy && login.isNotBlank() && (password.isNotBlank() || AgendaStore.isConnected(context, profile)),
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                scope.launch {
                                    busy = true
                                    status = "Łączenie z Librusem…"
                                    try {
                                        val finalPassword = if (password.isNotBlank()) password else AgendaStore.password(context, profile).orEmpty()
                                        AgendaStore.saveCredentials(context, profile, login, finalPassword)
                                        password = ""
                                        val result = withContext(Dispatchers.IO) { SyncEngine.syncProfile(context, profile) }
                                        status = result.message
                                        events = AgendaStore.allEvents(context, profile)
                                        SyncScheduler.schedulePeriodic(context)
                                    } catch (error: Exception) {
                                        status = friendlyError(error)
                                    } finally { busy = false }
                                }
                            }
                        ) { Text(if (busy) "Łączenie…" else "Zapisz konto i synchronizuj") }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            OutlinedButton(
                                enabled = !busy && AgendaStore.isConnected(context, profile),
                                modifier = Modifier.weight(1f),
                                onClick = {
                                    scope.launch {
                                        busy = true
                                        status = "Synchronizuję…"
                                        try {
                                            val result = withContext(Dispatchers.IO) { SyncEngine.syncProfile(context, profile) }
                                            status = result.message
                                            events = AgendaStore.allEvents(context, profile)
                                        } catch (error: Exception) {
                                            status = friendlyError(error)
                                        } finally { busy = false }
                                    }
                                }
                            ) { Text("Synchronizuj teraz") }
                            OutlinedButton(
                                enabled = !busy && AgendaStore.isConnected(context, profile),
                                onClick = {
                                    AgendaStore.clearCredentials(context, profile)
                                    AgendaStore.clearProfileData(context, profile)
                                    androidx.work.WorkManager.getInstance(context).cancelAllWorkByTag("reminders_$profile")
                                    events = emptyList()
                                    status = "Konto odłączone"
                                    UpcomingWidget.refresh(context)
                                }
                            ) { Text("Odłącz") }
                        }
                    }
                }

                val last = AgendaStore.lastSync(context, profile)
                StatusCard(
                    status = status,
                    busy = busy,
                    lastSync = if (last > 0) SimpleDateFormat("dd.MM.yyyy, HH:mm", Locale("pl", "PL")).format(Date(last)) else null
                )
                Text("Widżet: przytrzymaj ekran główny telefonu, wybierz Widżety → LibrusSync. Strzałkami zmienisz Janka i Franka bez otwierania aplikacji.", color = Muted, fontSize = 12.sp)
                Text("Synchronizacja w tle jest okresowa (co około 6 godzin) i zależy od ograniczeń baterii oraz systemu Android.", color = Muted, fontSize = 11.sp)
            }
        }
    }
}

private fun switchProfile(next: String, prefs: android.content.SharedPreferences, set: (String) -> Unit) {
    prefs.edit().putString("active_profile", next).apply()
    set(next)
}

@Composable
private fun ProfileButton(label: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val background by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
        label = "profile-button-color"
    )
    Button(
        onClick = onClick,
        modifier = modifier.animateContentSize(),
        shape = RoundedCornerShape(18.dp),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = if (selected) 3.dp else 0.dp),
        colors = ButtonDefaults.buttonColors(containerColor = background, contentColor = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)
    ) {
        AnimatedContent(targetState = selected, label = "profile-button-label") { active ->
            Text(if (active) "●  $label" else label, fontSize = 14.sp)
        }
    }
}

@Composable
private fun EventRow(event: SchoolEvent) {
    Surface(
        modifier = Modifier.fillMaxWidth().animateContentSize(),
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(16.dp)
    ) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(event.subject.ifBlank { event.category.ifBlank { "Praca szkolna" } }, color = MaterialTheme.colorScheme.onSurface, fontSize = 14.sp)
                Text(event.title, color = Muted, fontSize = 11.sp, maxLines = 2)
            }
            Spacer(Modifier.width(10.dp))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(event.countdown, color = MaterialTheme.colorScheme.primary, fontSize = 12.sp)
                Text(event.dateLabel, color = Muted, fontSize = 11.sp)
            }
        }
    }
}

@Composable
private fun StatusCard(status: String, busy: Boolean, lastSync: String?) {
    val normalized = status.lowercase()
    val isError = !busy && listOf("nieprawid", "błąd", "nie udało", "nie można", "wystąpi", "brak połąc", "brak login", "brak hasła", "wygas", "captcha", "nie został", "nie udostępnił", "nie odczytać", "nie odpowiada", "ograniczył", "niedostęp", "dodatkowego potwierdzenia").any { normalized.contains(it) }
    val isSuccess = !busy && (normalized.startsWith("zsynchronizowano") || normalized.startsWith("zakończono synchronizację") || normalized == "konto zapisane • gotowe do synchronizacji")
    val accent = when {
        isError -> Color(0xFFFF8A9A)
        isSuccess -> Color(0xFF7FE0B2)
        else -> Purple
    }
    val panel = when {
        isError -> if (isDarkThemeColor()) Color(0xFF38232D) else Color(0xFFFFE9EC)
        isSuccess -> if (isDarkThemeColor()) Color(0xFF1D342F) else Color(0xFFE5F5EC)
        else -> MaterialTheme.colorScheme.surface
    }
    Card(
        modifier = Modifier.fillMaxWidth().animateContentSize(),
        colors = CardDefaults.cardColors(containerColor = panel),
        shape = RoundedCornerShape(24.dp)
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                Surface(color = accent.copy(alpha = 0.16f), shape = RoundedCornerShape(50)) {
                    Text(
                        when { busy -> "…" ; isError -> "!" ; isSuccess -> "✓" ; else -> "●" },
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                        color = accent, fontSize = 14.sp
                    )
                }
                Text(
                    when { busy -> "Synchronizacja w toku" ; isError -> "Coś poszło nie tak" ; isSuccess -> "Wszystko gotowe" ; else -> "Status konta" },
                    color = accent, fontSize = 13.sp
                )
            }
            if (busy) {
                LinearProgressIndicator(
                    Modifier.fillMaxWidth(),
                    color = Purple,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant
                )
            }
            Text(status, color = Color.White, fontSize = 13.sp)
            Text(
                lastSync?.let { "Ostatnia synchronizacja: $it" } ?: "Brak zakończonej synchronizacji",
                color = Muted, fontSize = 11.sp
            )
        }
    }
}

private fun friendlyError(error: Throwable): String {
    val message = error.message.orEmpty()
    val normalized = message.lowercase()
    return when {
        normalized.contains("nieprawidłowy login") || normalized.contains("nieprawidlowy login") ->
            "Nieprawidłowy login lub hasło. Sprawdź dane konta Librus i spróbuj ponownie."
        normalized.contains("captcha") || normalized.contains("dodatkowego potwierdzenia") ->
            "Librus wymaga dodatkowego potwierdzenia logowania. Dokończ je w oficjalnej aplikacji lub przeglądarce."
        normalized.contains("timeout") || normalized.contains("przekroczył limit czasu") ->
            "Połączenie z Librusem trwało zbyt długo. Sprawdź internet i spróbuj ponownie."
        normalized.contains("internet") || normalized.contains("połączyć się") ->
            "Nie można połączyć się z Librusem. Sprawdź połączenie internetowe."
        normalized.contains("sesja") ->
            "Sesja Librusa wygasła. Połącz konto ponownie, wpisując login i hasło."
        normalized.contains("429") || normalized.contains("za dużo prób") ->
            "Librus ograniczył liczbę prób. Odczekaj chwilę i spróbuj ponownie."
        message.isBlank() -> "Coś poszło nie tak. Spróbuj ponownie za chwilę."
        else -> message
    }
}
