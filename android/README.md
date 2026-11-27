# LibrusSync Android — 0.2.0

Pierwszy natywny szkielet Androida, rozwijany obok istniejącej aplikacji iOS. Nie zmienia kodu iOS.

## Wersja 0.2.0
- Projekt Android Studio: Kotlin + Jetpack Compose.
- Dwa profile uczniów: Janek i Franek.
- Przełączanie aktywnego profilu.
- Pierwszy widżet ekranu głównego Androida (AppWidget), odświeżany po zmianie profilu.
- Widżet pokazuje nazwę ucznia, najbliższy termin i odliczanie, gdy dane są dostępne.
- Puste stany zamiast fikcyjnych terminów, dopóki nie ma synchronizacji.

## Ograniczenia tej wersji
Logowanie Librus, pobieranie HomeWorks, bezpieczne przechowywanie poświadczeń, synchronizacja w tle i wiele wpisów w dużym widżecie są zaplanowane na kolejne wydanie. Wersja 0.2.0 nie pobiera jeszcze danych z kont Librus.

## Budowanie
Otwórz katalog android w Android Studio (JDK 17, Android SDK 35), poczekaj na synchronizację Gradle i uruchom konfigurację app.
