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
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
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

    MaterialTheme(colorScheme = darkColorScheme(
        background = Navy, surface = Panel, primary = Purple,
        onBackground = Color.White, onSurface = Color.White
    )) {
        Surface(Modifier.fillMaxSize(), color = Navy) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("LibrusSync", fontSize = 28.sp, color = Color.White)
                        Text("Sprawdziany i kartkówki • Android", color = Muted, fontSize = 12.sp)
                    }
                    Surface(color = Color(0xFF30264F), shape = RoundedCornerShape(50)) {
                        Text("1.0.0", Modifier.padding(horizontal = 12.dp, vertical = 7.dp), color = Purple, fontSize = 12.sp)
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
                                status = error.message ?: "Wystąpił błąd synchronizacji."
                            } finally { busy = false }
                        }
                    }
                ) { Text("Synchronizuj Janka i Franka") }

                Card(colors = CardDefaults.cardColors(containerColor = Panel), shape = RoundedCornerShape(22.dp)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("NAJBLIŻSZE PRACE", color = Purple, fontSize = 11.sp)
                        Text(name.ifBlank { if (profile == "janek") "Janek" else "Franek" }, fontSize = 22.sp)
                        if (events.isEmpty()) {
                            Text("Nie ma jeszcze pobranych sprawdzianów ani kartkówek.", color = Muted)
                            Text("Połącz konto Librus, aby pobrać terminy.", color = Muted, fontSize = 12.sp)
                        } else {
                            events.take(5).forEach { event ->
                                EventRow(event)
                            }
                            if (events.size > 5) Text("i jeszcze ${events.size - 5} kolejnych…", color = Muted, fontSize = 12.sp)
                        }
                    }
                }

                Card(colors = CardDefaults.cardColors(containerColor = Panel), shape = RoundedCornerShape(20.dp)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                        Text("KONTO LIBRUS", color = Purple, fontSize = 11.sp)
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
                                        status = error.message ?: "Nie udało się bezpiecznie zapisać danych konta."
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
                                            status = error.message ?: "Błąd synchronizacji."
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

                Card(colors = CardDefaults.cardColors(containerColor = Panel), shape = RoundedCornerShape(18.dp)) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("STATUS", color = Purple, fontSize = 11.sp)
                        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Purple)
                        Text(status, color = Color.White, fontSize = 13.sp)
                        val last = AgendaStore.lastSync(context, profile)
                        Text(if (last > 0) "Ostatnia synchronizacja: ${SimpleDateFormat("dd.MM.yyyy, HH:mm", Locale("pl", "PL")).format(Date(last))}" else "Brak zakończonej synchronizacji", color = Muted, fontSize = 11.sp)
                    }
                }
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
    Button(onClick = onClick, modifier = modifier, colors = ButtonDefaults.buttonColors(
        containerColor = if (selected) Purple else Panel, contentColor = Color.White
    )) { Text(label) }
}

@Composable
private fun EventRow(event: SchoolEvent) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(event.subject.ifBlank { event.category.ifBlank { "Praca szkolna" } }, color = Color.White, fontSize = 14.sp)
            Text(event.title, color = Muted, fontSize = 11.sp, maxLines = 2)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(event.countdown, color = Color(0xFFFF9A83), fontSize = 12.sp)
            Text(event.dateLabel, color = Muted, fontSize = 11.sp)
        }
    }
}
