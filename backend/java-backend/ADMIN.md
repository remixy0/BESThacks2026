# Administrator, alarm i strefy wyłączone

## Uruchomienie i role

Zrestartuj backend. `schema.sql` automatycznie doda kolumnę `app_users.role`;
dotychczasowe konta i nowe rejestracje otrzymają `USER`. Rola jest zapisana w PostgreSQL.
Rejestracja nie pozwala nadać sobie uprawnień administratora.

Aby nadać rolę wybranemu istniejącemu kontu, wykonaj w pgAdmin Query Tool,
podstawiając jego rzeczywisty email:

```sql
UPDATE app_users SET role = 'ADMIN' WHERE email = 'twoj-email@example.com';
SELECT id, email, role FROM app_users WHERE email = 'twoj-email@example.com';
```

Następnie wyloguj to konto i zaloguj je ponownie. Uprawnienia są pobierane przy logowaniu;
zmiana roli w SQL nie zmienia już zalogowanych sesji. Analogicznie `role = 'USER'` odbiera
rolę przy kolejnym logowaniu. Login, rejestracja i `/api/auth/me` zwracają teraz także `role`.

Logowanie nadal korzysta z sesji i cookie `JSESSIONID`, zgodnie z `AUTH.md`.
Natywny iOS przekazuje cookie zalogowanego konta przy połączeniu WebSocket.
Nie wysyła emaila ani roli w wiadomościach pozycji. Backend odczytuje tożsamość z sesji.

## Połączenia

- Użytkownik: `ws://localhost:8081/ws/position` — dotychczasowe komendy `position`, `destination`, `cancel`.
- Administrator: `ws://localhost:8081/ws/admin` — obserwacja użytkowników i poniższe komendy.
- Administrator może też korzystać z własnej nawigacji przez `/ws/position`.
- Zwykły użytkownik otrzyma HTTP 403 przy próbie połączenia z `/ws/admin`; niezalogowany HTTP 401.
- Polecenia administracyjne na `/ws/position` są odrzucane.

Na telefonie użyj adresu komputera z backendem zamiast `localhost`.
Otwieranie adresu `ws://` w pasku przeglądarki nie tworzy klienta WebSocket.

Po połączeniu administrator otrzymuje `policy` (alarm, strefy, wyjścia), a następnie `positions`.
`positions` to pełny aktualny zestaw ostatnich lokalizacji, wysyłany również po aktualizacji
pozycji i rozłączeniu użytkownika:

```json
{
  "type": "positions",
  "users": [
    {"username": "user@example.com", "x": -0.5, "y": 51.9, "receivedAt": "2026-10-10T18:00:00Z"}
  ]
}
```

Lista obejmuje połączone konta, które przesłały co najmniej jedną pozycję.
Jedno konto pojawia się raz: przy kilku połączeniach wybierana jest najnowsza pozycja.
Po zamknięciu jednego połączenia może pozostać pozycja z drugiego.
Nie jest zapisywana historia lokalizacji. Czas `receivedAt` pozwala pokazać wiek pomiaru.
Zamknięte, wylogowane i wygasłe sesje są usuwane; kontrola wygasania działa co sekundę
oraz przed wysłaniem danych. Po wygaśnięciu należy zalogować się ponownie.

## Komendy administratora

Włączenie alarmu:

```json
{"type":"alarm","active":true}
```

Wyłączenie alarmu:

```json
{"type":"alarm","active":false}
```

Dodanie prostokąta w metrach, w tym samym układzie współrzędnych co pozycje:

```json
{"type":"zone.add","minX":10,"minY":10,"maxX":14,"maxY":16}
```

Backend nadaje strefie UUID. Odpowiedź `policy` zawiera pełną listę aktualnych stref,
w tym nowy identyfikator. Prostokąt musi mieć dodatnie wymiary i mieścić się w granicach
mapy. Można mieć maksymalnie 100 stref; nakładanie się prostokątów jest obsługiwane.

Usunięcie strefy — użyj identyfikatora z odpowiedzi:

```json
{"type":"zone.remove","id":"UUID-strefy"}
```

Ponowne pobranie stanu oraz pozycji:

```json
{"type":"snapshot"}
```

Po każdej poprawnej zmianie wszyscy administratorzy i połączeni użytkownicy otrzymują
`policy`. Użytkownicy, których pozycja/cel są już znane, dostają zaraz potem nową wiadomość
`navigation`, bez czekania na kolejny pomiar pozycji. Zmiany są wykonywane kolejno;
`revision` rośnie przy zmianie polityki, a `navigation.policyRevision` wskazuje jej wersję.
Nowe połączenie użytkownika podczas aktywnego alarmu lub przy istniejących strefach
otrzymuje bieżące `policy`; następnie należy przesłać pozycję.

Przykład struktury `policy`:

```json
{
  "type":"policy",
  "revision":1,
  "alarmActive":true,
  "zones":[],
  "exits":[{"x":0.1,"y":-62.3}]
}
```

Lista `exits` w rzeczywistej odpowiedzi pochodzi z mapy; powyżej pokazano jeden punkt
dla ilustracji formatu. Błędy mają postać `{"type":"error","code":"...","message":"..."}`.
Przykładowe kody: `INVALID_COMMAND`, `INVALID_ZONE`, `ZONE_NOT_FOUND`, `ZONE_LIMIT`.

## Zachowanie nawigacji

Alarm dotyczy także użytkowników bez wybranego celu i osób dołączających w jego trakcie.
Zastępuje cel zwykłej nawigacji wyjściem. W obecnej mapie wyjściami są punkty `approach`
dwóch POI oznaczonych jako `entrance`: wejście północne i południowe. Ich poprawne
oznaczenie w danych mapy określa, dokąd prowadzi alarm.

Backend oblicza trasy do dostępnych wyjść i wybiera najkrótszą z wyznaczonych tras,
uwzględniając przeszkody i strefy. Nie porównuje wyłącznie odległości w linii prostej.
Wyjście jest wybierane przy uruchomieniu alarmu i przeliczeniu po zmianie stref.
Algorytm nadal używa A* i wygładzania odcinków — długość jest długością znalezionej trasy,
a nie gwarantowanym globalnym optimum w przestrzeni ciągłej.

Podczas alarmu `destination` i `cancel` od użytkownika nie wyłączają ewakuacji.
Nowy cel zostaje zapamiętany na później; `cancel` usuwa zwykły cel.
Po odwołaniu alarmu backend wznawia nawigację do zapamiętanego celu lub zwraca `idle`.

Strefy blokują komórki siatki przecinające prostokąt powiększony o 30 cm odstępu.
Granice są zaokrąglane na zewnątrz do siatki, więc faktycznie blokowany obszar jest
nieco większy od prostokąta narysowanego przez administratora.

Jeżeli użytkownik znajduje się w nowej strefie, może ją opuścić, ale trasa nie może
do niej wrócić. Ściany pozostają nieprzekraczalne. Wyprowadzenie zwykle jest początkiem
normalnej trasy do celu. Jeżeli cel jest niedostępny, backend najpierw wyznacza drogę
do najbliższej dostępnej komórki poza strefami (`status: escaping`), a po jej opuszczeniu
zgłasza blokadę. Usunięcie strefy automatycznie wznawia trasę.

Dotychczasowy format `navigation` opisuje `NAVIGATION.md`. Dodano:

- `alarmActive`: czy trasa jest wykonywana podczas alarmu;
- `policyRevision`: wersja stanu alarmu/stref;
- `status: escaping`: idź do `nextWaypoint`, aby opuścić strefę; `destination` może
  wskazywać nadal zablokowany cel albo być null, gdy brak dostępnego wyjścia;
- `status: idle`: brak aktywnego celu, usuń poprzednią wskazówkę nawigacji.

Przy `escaping` odległość pozostała dotyczy drogi wyprowadzenia, nie zablokowanego celu.
Przy `blocked` nie ma `nextWaypoint`: aplikacja powinna usunąć starą wskazówkę i pokazać
powód, np. `DESTINATION_BLOCKED`, `NO_ROUTE`, `NO_REACHABLE_EXIT`, `NO_ESCAPE_ROUTE`.
Jeżeli nie ma fizycznie przejezdnej drogi, backend nie prowadzi przez ścianę.
Klient powinien obsługiwać `policy` niezależnie od potwierdzeń `position` i instrukcji
`navigation` — zdarzenia administracyjne mogą nadejść bez żądania użytkownika.

## Zakres przechowywania i testy

Role są trwałe w PostgreSQL. Alarm, strefy, lokalizacje i trasy są obecnie w pamięci
jednej instancji backendu: restart usuwa strefy i odwołuje alarm. Rozłączenie samego
administratora nie odwołuje alarmu ani stref.

Testy: `./mvnw.cmd test`. Obejmują role i odmowę dostępu, rzeczywiste połączenia WS,
powiadomienia administratora i użytkownika, wylogowanie administratora, zmianę trasy,
nakładające się strefy, wyprowadzenie z zablokowanego celu i alternatywne wyjścia.
