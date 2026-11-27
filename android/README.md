# LibrusSync Android — 1.0.0

Natywna aplikacja Android dla dwóch uczniów: Janek i Franek. Rozwijana niezależnie od aplikacji iOS.

## Funkcje
- Dwa oddzielne profile i niezależne konta Librus Synergia.
- Logowanie i pobieranie terminarza HomeWorks z Librusa.
- Wykrywanie sprawdzianów, kartkówek, testów i prac klasowych po treści/kategorii udostępnionej przez API.
- Lista najbliższych prac z odliczaniem i datą.
- Widżet Androida w małym i większym rozmiarze, z wyborem ucznia strzałkami.
- Powiadomienia o nowych/zmienionych pracach (po pierwszym imporcie) oraz przypomnienie przed terminem.
- Ręczna synchronizacja pojedynczego konta lub obu kont.
- Okresowa synchronizacja w tle przez WorkManager, co około 6 godzin (Android decyduje, kiedy wykona zadanie).
- Loginy i hasła szyfrowane AES-GCM z kluczem przechowywanym w Android Keystore.
- Brak danych konta w zwykłym SharedPreferences; wyłączone kopie zapasowe aplikacji.

## Pierwsze uruchomienie
1. Zainstaluj APK na telefonie mamy.
2. Wybierz profil Janek i wpisz dane konta Librus Synergia. Zapisz konto i poczekaj na wynik synchronizacji.
3. Wybierz profil Franek i wykonaj to samo dla drugiego konta.
4. Zezwól na powiadomienia.
5. Dodaj widżet: przytrzymaj ekran główny → Widżety → LibrusSync. Zmień rozmiar, aby pokazać 1–3 terminy. Strzałki przełączają profile.

## Synchronizacja i ograniczenia
- Logowanie korzysta z nieoficjalnego, nieudokumentowanego przepływu Librus Synergia OAuth/API, zgodnego z implementacją aplikacji iOS w tym repozytorium. Librus może zmienić endpointy, wprowadzić CAPTCHA lub dodatkową weryfikację. Aplikacja nie obchodzi CAPTCHA; w takim przypadku logowanie trzeba dokończyć oficjalną drogą i spróbować ponownie.
- Wydarzenia są klasyfikowane jako prace szkolne na podstawie nazw kategorii i tekstu dostępnego w HomeWorks. Jeśli szkoła nie zapisuje rodzaju pracy w tych polach, termin może nie zostać rozpoznany jako sprawdzian/kartkówka.
- WorkManager uruchamia synchronizację okresową z minimalną częstotliwością zależną od Androida, sieci i optymalizacji baterii; nie gwarantuje dokładnie 6 godzin ani działania w czasie rzeczywistym.
- Przypomnienia wymagają zgody na powiadomienia. Android może opóźnić pracę w tle w trybie oszczędzania baterii.
- Pierwsza synchronizacja nie wysyła powiadomień o wszystkich już istniejących terminach, aby nie zasypać użytkownika alertami.

## Budowanie
Wymagane JDK 17, Android SDK 35 i Gradle 8.9. Otwórz katalog `android/` w Android Studio lub uruchom:
```bash
gradle -p android assembleDebug
```
Artefakt GitHub Actions `LibrusSync-Android-1.0.0-debug` zawiera instalowalny APK debug. Nie jest to podpisane wydanie Google Play.
