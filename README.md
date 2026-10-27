# LibrusSync

Natywna aplikacja SwiftUI dla iOS 17+, która synchronizuje wydarzenia z kalendarza iCalendar (.ics) z Kalendarzem Apple. Nie wymaga własnego backendu.

## Co jest w tej wersji

- Pobieranie kalendarza przez HTTPS.
- Parsowanie podstawowych wydarzeń iCalendar (VEVENT, UID, SUMMARY, DTSTART, DTEND, DESCRIPTION, TZID).
- Wykrywanie nowych i zmienionych wydarzeń na podstawie UID i treści.
- Zapisywanie wydarzeń w osobnym kalendarzu Apple o nazwie LibrusSync.
- Lokalne powiadomienia o nowych i zaktualizowanych wpisach.
- Zapisywanie źródła kalendarza w iOS Keychain.
- Próba synchronizacji w tle przez BGAppRefreshTask.
- GitHub Actions budujący aplikację na symulator i publikujący ZIP jako artefakt.

## Ważne ograniczenie integracji z Librusem

Ta wersja **nie loguje się bezpośrednio do konta Librus i nie pobiera jeszcze terminarza przez jego stronę**. Do synchronizacji wymaga adresu kalendarza HTTPS w formacie .ics. Nie zakładaj, że Librus udostępnia taki adres w Twojej szkole — trzeba go mieć z obsługiwanego źródła kalendarza. Nie wpisuj tutaj hasła do Librusa.

Bezpośrednie logowanie przez nieoficjalne, odtwarzane API/HTML byłoby kruche ze względu na zmiany procesu logowania. Należy zaimplementować i przetestować osobny adapter Librus przed nazywaniem tej integracji gotową.

## Jak uruchomić

1. Otwórz LibrusSync.xcodeproj w Xcode na macOS.
2. Wybierz schemat LibrusSync i symulator iPhone’a.
3. Uruchom aplikację.
4. Wklej prywatny adres kalendarza .ics rozpoczynający się od https:// i wybierz Sprawdź teraz.
5. Zaakceptuj dostęp do Kalendarza Apple. Wydarzenia będą dodawane do kalendarza LibrusSync.

Pierwsza synchronizacja importuje zdarzenia jako stan początkowy bez wysyłania serii powiadomień. Kolejne synchronizacje powiadamiają o nowych lub zmienionych wydarzeniach.

## GitHub Actions

Workflow znajduje się w .github/workflows/ios-build.yml. Uruchamia się po pushu, pull requeście i ręcznie z zakładki Actions. Po udanym buildzie pobierz artefakt LibrusSync-iOS-Simulator.

Artefakt symulatora nie jest plikiem IPA do instalacji na iPhonie. IPA dla urządzenia wymaga kompilacji na iOS Device oraz podpisywania certyfikatem i profilem provisioning.

## Ograniczenia iOS

BGAppRefreshTask nie gwarantuje uruchomienia o konkretnej godzinie. iOS sam dobiera moment wybudzenia, a wymuszone zamknięcie aplikacji może zatrzymać zadania w tle do kolejnego uruchomienia.

## Prywatność

- Adres kalendarza jest przechowywany w Keychain urządzenia.
- Login i hasło do Librusa nie są zbierane ani przechowywane.
- Aplikacja nie wysyła danych do własnego serwera.
- Adres kalendarza może sam w sobie być prywatnym linkiem — nie udostępniaj go publicznie.
