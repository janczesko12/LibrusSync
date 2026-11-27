# LibrusSync Android — 0.3.0

Widget-first Android release, rozwijany obok istniejącej aplikacji iOS.

## Nowości 0.3.0
- Widżet przełącza profil Janek / Franek bez otwierania aplikacji (strzałki).
- Widżet ma czytelny nagłówek ucznia, obszar najbliższego terminu i stan pusty.
- Dotknięcie widżetu otwiera aplikację.
- Aktualizacja widżetu po zmianie profilu lub nazw uczniów w aplikacji.
- Podniesiono versionCode do 30 i versionName do 0.3.0.

## Status synchronizacji
W tej wersji synchronizacja Librus nie jest jeszcze podłączona do Androida. Widżet nie pokazuje fikcyjnych sprawdzianów. Obsługa logowania, pobierania HomeWorks dla dwóch niezależnych kont, bezpiecznego magazynu poświadczeń i synchronizacji w tle pozostaje kolejnym etapem. Nie wpisuj haseł Librus w żadnym polu testowym.

## Budowanie
Otwórz katalog android w Android Studio (JDK 17, Android SDK 35), zsynchronizuj Gradle i uruchom konfigurację app.
