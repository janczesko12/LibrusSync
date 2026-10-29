# LibrusSync Widget API

Vercel Function dla zdalnego widżetu LibrusSync.

## Deployment

Projekt Vercel: `librussync-widget-api`. Root deploymentu zawiera ten folder (`widget-api`).
Połączenie z prywatnym Vercel Blob wymaga automatycznie przypisanej zmiennej `BLOB_READ_WRITE_TOKEN`.

## API

- `POST /api/events` z nagłówkiem `Authorization: Bearer <write-token>` oraz JSON `{ id, readToken, events }` publikuje maksymalnie 30 wydarzeń.
- `GET /api/events?id=<uuid>` z nagłówkiem `Authorization: Bearer <read-token>` zwraca wydarzenia dla widżetu.
- W bazie przechowywane są hashe tokenów, nie surowe tokeny. Login i hasło Librus nie są przesyłane do tego API.
- Wszystkie odpowiedzi prywatne wysyłane są z `Cache-Control: private, no-store`.

Zapisane wpisy zawierają tytuły i daty wydarzeń szkolnych, dlatego nie należy udostępniać kodu konfiguracji widżetu.
