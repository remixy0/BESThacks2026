# Backend w Dockerze

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
