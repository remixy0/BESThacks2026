# Backend w Dockerze

## Spring Boot i PostgreSQL razem — Docker Compose

W `backend/java-backend/compose.yaml` są dwie usługi: `backend` i `postgres`.
Backend buduje się z istniejącego Dockerfile, a PostgreSQL używa obrazu `18-bookworm`.
Backend czeka na gotowość bazy, po czym istniejący `schema.sql` tworzy tabele aplikacji.
Konta przechowuje nazwany wolumen `postgres_data`; baza nie publikuje portu na hosta.
Konfiguracja korzysta z [healthcheck i service_healthy](https://docs.docker.com/compose/how-tos/startup-order/)
oraz [katalogu danych i inicjalizacji oficjalnego obrazu PostgreSQL](https://hub.docker.com/_/postgres).

Wymagany jest Docker z dodatkiem Compose. Na Windows uruchom Docker Desktop
w trybie kontenerów Linux. Komendy wykonuj w katalogu backendu:

```powershell
cd C:\Users\Uranx\IdeaProjects\Hackathon\BESThacks2026\backend\java-backend
Copy-Item .env.example .env
```

Jeśli `.env` już istnieje, edytuj go zamiast kopiować szablon ponownie.
W `.env` ustaw własne, niepuste `DB_PASSWORD`; możesz też zmienić `DB_NAME`, `DB_USER`
i `BACKEND_PORT`. Dla haseł zawierających `$` lub `#` użyj pojedynczych cudzysłowów
w pliku, np. `DB_PASSWORD='twoje-haslo'`. `.env` jest ignorowany przez Git i nie trafia do obrazu.

Następnie:

```powershell
docker compose config --quiet
docker compose up -d --build
docker compose ps
docker compose logs -f backend
```

Pierwsze budowanie pobiera obrazy i zależności oraz uruchamia testy. Przerwanie podglądu
logów przez Ctrl+C nie zatrzymuje kontenerów. Gdy backend wystartuje, sprawdź:

```powershell
curl.exe -i http://localhost:8081/api/auth/csrf
```

Swagger: `http://localhost:8081/swagger-ui/index.html`.
WebSockety: `ws://localhost:8081/ws/position` i `ws://localhost:8081/ws/admin`.
Jeśli zmienisz `BACKEND_PORT`, używaj tego portu w powyższych adresach.
Jeśli port 8081 zajmuje aplikacja z IntelliJ, zatrzymaj ją albo ustaw `BACKEND_PORT=8082`.

Backend łączy się przez `jdbc:postgresql://postgres:5432/museum` (lub inną `DB_NAME`).
Host `postgres` oznacza usługę w sieci Compose. Nie ustawiaj tu `localhost` ani
`host.docker.internal`. Compose sam przekazuje `DB_URL`, `DB_USER` i `DB_PASSWORD`;
zmienne ustawione wyłącznie w IntelliJ nie konfigurują kontenerów.

**To nowa baza w Dockerze.** Obecne konta z PostgreSQL uruchomionego poza Dockerem
nie zostaną automatycznie przeniesione. Zarejestruj konto ponownie lub przenieś dane
przez eksport/import bazy, jeśli chcesz je zachować.

### Zatrzymanie i aktualizacja

```powershell
docker compose down
docker compose up -d --build
```

`down` usuwa kontenery i sieć, ale zachowuje wolumen z bazą. Nie dodawaj `-v`, jeśli chcesz
zachować konta — ta opcja usuwa także wolumen. Wolumen nie zastępuje kopii zapasowej.
Zmiana hasła/nazwy/użytkownika w `.env` nie zmienia istniejącej bazy: zmienne inicjalizacji
PostgreSQL działają przy pierwszym uruchomieniu pustego wolumenu. Zmiany w istniejącej
bazie trzeba wykonać także w SQL. Nie zmieniaj głównej wersji obrazu PostgreSQL bez migracji danych.

### Konsola PostgreSQL

Wejdź do kontenera i otwórz konsolę, która użyje nazw z konfiguracji:

```powershell
docker compose exec postgres sh
```

Następnie wewnątrz kontenera:

```sh
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

Wyjdź z `psql` przez `\q`, a z powłoki przez `exit`.

### Uruchomienie na serwerze

Na serwerze z Docker Compose pobierz repozytorium, przejdź do `backend/java-backend`,
utwórz `.env` i wykonaj te same komendy. To uruchomi backend na porcie hosta
`BACKEND_PORT`. Aplikacja na telefonie używa adresu serwera, np.
`http://ADRES_SERWERA:8081`, nie `localhost` telefonu.

Przy domenie i HTTPS potrzebujesz reverse proxy przekazującego HTTP i upgrade WebSocket.
Dla proxy na tym samym hoście ustaw `BACKEND_BIND_ADDRESS=127.0.0.1`,
`COOKIE_SECURE=true`, `FORWARD_HEADERS_STRATEGY=framework` i kieruj proxy na port backendu.
Przy proxy w kontenerze podłącz je do sieci Compose i kieruj do `backend:8081`.
Compose nie konfiguruje domeny ani certyfikatu TLS; dalsze ustawienia opisano niżej.
Uruchamiaj jedną instancję backendu, ponieważ sesje i stan nawigacji pozostają w pamięci.

W tym prostym zestawie konto `DB_USER` jest kontem inicjalizującym PostgreSQL i ma uprawnienia
superuser. Przy docelowym wdrożeniu można wydzielić osobne konto aplikacji z uprawnieniami
do jej schematu, w tym DDL potrzebnym przez obecny `schema.sql`.

Dockerfile znajduje się w `backend/java-backend`. Buduje aplikację za pomocą Maven Wrapper
i Java 25, uruchamia testy, a następnie kopiuje gotowy JAR do obrazu z Java 25 JRE.
Kontener działa jako użytkownik bez uprawnień roota. Aktualna mapa jest pakowana w JAR.

## Budowanie

Z głównego katalogu repozytorium:

```sh
docker build -t museum-backend:latest ./backend/java-backend
```

Na platformie hostingowej ustaw kontekst budowania na `backend/java-backend`
i ścieżkę Dockerfile na `Dockerfile` względem tego kontekstu.
Pierwsze budowanie wymaga internetu do pobrania obrazów, Mavena i zależności.
Kolejne budowania korzystają z cache Maven w BuildKit.

## Konfiguracja uruchomienia

| Zmienna | Wymagana | Przykład / zastosowanie |
|---|---|---|
| `DB_URL` | Tak | `jdbc:postgresql://HOST_BAZY:5432/museum` |
| `DB_USER` | Tak | Użytkownik PostgreSQL |
| `DB_PASSWORD` | Tak | Hasło PostgreSQL |
| `SERVER_PORT` | Nie | Port wewnątrz kontenera; domyślnie `8081` |
| `JAVA_TOOL_OPTIONS` | Nie | Opcje JVM, np. `-XX:MaxRAMPercentage=75` |
| `SERVER_SERVLET_SESSION_COOKIE_SECURE` | Dla HTTPS | `true` — cookie sesji tylko przez HTTPS |
| `SERVER_FORWARD_HEADERS_STRATEGY` | Za zaufanym proxy | `framework` — obsługa przekazanych nagłówków hosta i protokołu |

Nie dodawaj danych dostępu do Dockerfile. W hostingu ustaw powyższe wartości jako
zmienne środowiskowe lub sekrety. Backend wymaga już działającego PostgreSQL i uprawnień
do tworzenia/aktualizowania tabel przez `schema.sql` przy uruchomieniu.

Jeżeli dostawca narzuca port przez zmienną `PORT`, przekaż jej wartość jako `SERVER_PORT`
w konfiguracji hostingu. Samo `PORT` nie jest obecnie odczytywane przez aplikację.
`EXPOSE` opisuje port domyślny; nie publikuje portu na hoście.

## Lokalne uruchomienie

W osobnym pliku poza repozytorium, np. `museum-backend.env`, ustaw:

```dotenv
DB_URL=jdbc:postgresql://host.docker.internal:5432/museum
DB_USER=twoj_uzytkownik
DB_PASSWORD=twoje_haslo
```

`host.docker.internal` w tym przykładzie oznacza PostgreSQL uruchomiony na komputerze
z Docker Desktop. Jeśli baza działa w innym kontenerze na wspólnej sieci Docker,
użyj nazwy jego usługi lub kontenera. Jeśli to baza zewnętrzna, użyj jej hosta.
`localhost` w kontenerze backendu oznacza sam kontener backendu.

Uruchom, podając rzeczywistą ścieżkę do pliku środowiska:

```sh
docker run --detach --name museum-backend --env-file /sciezka/do/museum-backend.env -p 8081:8081 museum-backend:latest
```

W PowerShell również można użyć jednej linii; przy ścieżce ze spacjami otocz ją cudzysłowami.
Nie zapisuj pliku z rzeczywistym hasłem w repozytorium.

Sprawdzenie:

```sh
docker logs -f museum-backend
curl http://localhost:8081/api/auth/csrf
```

Swagger: `http://localhost:8081/swagger-ui/index.html`.
WebSockety: `ws://localhost:8081/ws/position` i `ws://localhost:8081/ws/admin`.
Logowanie oraz cookie są wymagane zgodnie z [INTEGRATION.md](INTEGRATION.md).
Przy lokalnym HTTP pozostaw `SERVER_SERVLET_SESSION_COOKIE_SECURE` wyłączone.

## Deployment za HTTPS

Hosting lub reverse proxy powinno przekazywać HTTP i obsługiwać upgrade WebSocket
dla `/ws/position` oraz `/ws/admin`. Używaj wtedy `https://` i `wss://`.
Przy zaufanym proxy terminującym TLS ustaw:

```dotenv
SERVER_SERVLET_SESSION_COOKIE_SECURE=true
SERVER_FORWARD_HEADERS_STRATEGY=framework
```

Frontend przeglądarkowy nadal wymaga zgodnego originu lub uzgodnionej konfiguracji CORS
i originów WebSocket. Dockerfile nie zmienia zasad logowania ani dostępu do API.

Na obecnym etapie uruchamiaj **jedną instancję backendu**: sesje, alarm, strefy i pozycje
są przechowywane w jej pamięci. Restart kontenera resetuje te dane i wymaga ponownego
logowania. Konta i role pozostają w zewnętrznej bazie PostgreSQL.

## Obrazy bazowe

Dockerfile korzysta z oficjalnych obrazów Eclipse Temurin `25-jdk-noble` i `25-jre-noble`.
Lista publikowanych tagów: [Docker Official Images — Eclipse Temurin](https://github.com/docker-library/official-images/blob/master/library/eclipse-temurin).
