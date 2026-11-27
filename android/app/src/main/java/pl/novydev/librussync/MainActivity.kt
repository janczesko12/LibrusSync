package pl.novydev.librussync

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Navy = Color(0xFF10111F)
private val Panel = Color(0xFF1B1D30)
private val Purple = Color(0xFF9B7BFF)

class MainActivity : ComponentActivity() {
 override fun onCreate(savedInstanceState: Bundle?) {
  super.onCreate(savedInstanceState)
  val prefs = getSharedPreferences("librussync", MODE_PRIVATE)
  setContent {
   MaterialTheme(colorScheme = darkColorScheme(background=Navy, surface=Panel, primary=Purple, onBackground=Color.White, onSurface=Color.White)) {
    var active by remember { mutableStateOf(prefs.getString("active_profile", "Janek") ?: "Janek") }
    var janek by remember { mutableStateOf(prefs.getString("Janek_name", "Janek") ?: "Janek") }
    var franek by remember { mutableStateOf(prefs.getString("Franek_name", "Franek") ?: "Franek") }
    Surface(Modifier.fillMaxSize(), color=Navy) {
     Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement=Arrangement.spacedBy(16.dp)) {
      Row(verticalAlignment=Alignment.CenterVertically) {
       Column(Modifier.weight(1f)) {
        Text("LibrusSync", fontSize=27.sp, color=Color.White)
        Text("Wszystkie szkolne terminy w jednym miejscu", color=Color.LightGray, fontSize=12.sp)
       }
       Text("0.2.0", color=Purple)
      }
      Row(Modifier.fillMaxWidth(), horizontalArrangement=Arrangement.spacedBy(8.dp)) {
       ProfileButton(janek, active=="Janek", Modifier.weight(1f)) {
        active="Janek"; prefs.edit().putString("active_profile", active).apply(); UpcomingWidget.refresh(this@MainActivity)
       }
       ProfileButton(franek, active=="Franek", Modifier.weight(1f)) {
        active="Franek"; prefs.edit().putString("active_profile", active).apply(); UpcomingWidget.refresh(this@MainActivity)
       }
      }
      Card(colors=CardDefaults.cardColors(containerColor=Panel), shape=RoundedCornerShape(22.dp)) {
       Column(Modifier.padding(18.dp), verticalArrangement=Arrangement.spacedBy(10.dp)) {
        Text("NAJBLIŻSZE PRACE", color=Purple, fontSize=11.sp)
        Text(if(active=="Janek") janek else franek, fontSize=23.sp)
        Text("Sprawdziany i kartkówki pojawią się tutaj po podłączeniu konta Librus.", color=Color.LightGray)
        Text("Widżet jest gotowy do dodania na ekran główny.", color=Color.White, fontSize=13.sp)
       }
      }
      Text("USTAWIENIA UCZNIÓW", color=Purple, fontSize=12.sp)
      OutlinedTextField(value=janek, onValueChange={ janek=it; prefs.edit().putString("Janek_name",it).apply(); UpcomingWidget.refresh(this@MainActivity) }, label={Text("Pierwszy uczeń")}, modifier=Modifier.fillMaxWidth(), singleLine=true)
      OutlinedTextField(value=franek, onValueChange={ franek=it; prefs.edit().putString("Franek_name",it).apply() }, label={Text("Drugi uczeń")}, modifier=Modifier.fillMaxWidth(), singleLine=true)
      Button(onClick={ prefs.edit().putString("active_profile",active).apply(); UpcomingWidget.refresh(this@MainActivity) }, modifier=Modifier.fillMaxWidth()) { Text("Zapisz i odśwież widżet") }
      Card(colors=CardDefaults.cardColors(containerColor=Panel), shape=RoundedCornerShape(18.dp)) {
       Column(Modifier.padding(16.dp), verticalArrangement=Arrangement.spacedBy(6.dp)) {
        Text("Synchronizacja Librus", color=Color.White)
        Text("Logowanie i automatyczne pobieranie danych będą kolejnym etapem. W tej wersji nie wpisuj tutaj haseł – synchronizacja nie jest jeszcze wdrożona.", color=Color.LightGray, fontSize=12.sp)
       }
      }
     }
    }
   }
  }
 }
}

@Composable
private fun ProfileButton(label:String, selected:Boolean, modifier:Modifier, onClick:()->Unit) {
 Button(onClick=onClick, modifier=modifier, colors=ButtonDefaults.buttonColors(containerColor=if(selected) Purple else Panel, contentColor=Color.White)) { Text(label.ifBlank { "Uczeń" }) }
}
