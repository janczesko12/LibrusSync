# LibrusSync

Natywna aplikacja SwiftUI dla iOS 17+, która pobiera terminarz z Librus Synergia, wykrywa nowe i zmienione wpisy i dodaje je do wybranego kalendarza Apple. Nie wymaga własnego backendu.

## Funkcje

- Bezpośrednie logowanie do Librus Synergia przez nieoficjalny, społecznościowo poznany przepływ logowania/API.
- Pobieranie terminarza z endpointu HomeWorks (sprawdziany, kartkówki, spotkania i inne wpisy udostępnione przez konto).
- Wzbogacanie tytułów o nazwę kategorii i przedmiotu, jeśli API je zwraca.
- Wykrywanie nowych i zmienionych wydarzeń na podstawie identyfikatora i treści.
- Wybór zapisywalnego kalendarza Apple, np. iCloud lub lokalnego.
- Powiadomienia lokalne o nowych i zmienionych wpisach.
- Przechowywanie loginu i hasła tylko w Keychain urządzenia.
- Automatyczna synchronizacja przy powrocie aplikacji na pierwszy plan (jeśli od ostatniej synchronizacji minęło co najmniej 5 minut).
- Powiadomienia lokalne o nowych i zmienionych wpisach; system poprosi o zgodę na powiadomienia.
- Próba synchronizacji w tle przez BGAppRefreshTask.
- GitHub Actions budujący aplikację na iPhone'a (niepodpisany IPA) i symulator.

## Pierwsze uruchomienie

1. Otwórz aplikację na iPhonie.
2. Wprowadź login i hasło do konta **Librus Synergia**.
3. Kliknij **Połącz z Librusem** i zaakceptuj żądanie dostępu do Kalendarza Apple.
4. W sekcji Kalendarz Apple wybierz docelowy kalendarz.
5. Użyj **Synchronizuj teraz** do ręcznej synchronizacji.

## Ważne ograniczenia

- Integracja używa nieoficjalnego API i nie jest wspierana przez Librus. Proces logowania i struktura danych mogą się zmienić; może też pojawić się dodatkowa weryfikacja/CAPTCHA. Aplikacja nie próbuje obchodzić takich zabezpieczeń.
- iOS nie pozwala zwykłej aplikacji niezawodnie wykrywać każdego odblokowania telefonu. Synchronizacja uruchamia się, gdy LibrusSync wraca na pierwszy plan, z ograniczeniem do jednego automatycznego sprawdzenia na 5 minut.
- BGAppRefreshTask nie gwarantuje konkretnej częstotliwości. iOS sam dobiera termin wybudzenia, a wymuszone zamknięcie aplikacji może zatrzymać zadania w tle.
- Powiadomienia wymagają zgody w ustawieniach iOS; pierwsza synchronizacja nie wysyła alertów dla wszystkich już istniejących wpisów.
- Jeśli konto szkolne nie ma dostępu do terminarza, aplikacja nie będzie mogła go pobrać.
- IPA z GitHub Actions jest niepodpisany i przed instalacją na iPhonie wymaga podpisania.

## Prywatność

- Login i hasło są zapisane w Keychain urządzenia.
- Sesja HTTP jest utrzymywana w systemowym magazynie ciasteczek aplikacji.
- Dane nie są wysyłane do własnego serwera.
- Nie umieszczaj danych konta w Issue, zrzutach ekranu ani commitach.
