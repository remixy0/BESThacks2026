# Pozycja użytkownika i nawigacja

Adres lokalny: `ws://localhost:8081/ws/position` (dostosuj port do backendu).
To zwykły WebSocket z wiadomościami JSON, bez STOMP i SockJS.

Najpierw zaloguj się przez `/api/auth/login`, zgodnie z `AUTH.md`.
Połączenie używa istniejącego ciasteczka sesji. Identyfikator użytkownika
pochodzi z sesji. Klient może przesyłać pozycję, wybierać cel i anulować nawigację.
Pełny protokół prowadzenia opisano w `NAVIGATION.md`.

## Format wiadomości

```json
{"x":1.2,"y":3.4}
```

`x` i `y` to skończone liczby w **metrach**, na jednym piętrze. Oba pola
są wymagane. Ciągi tekstowe, `null`, inne pola i niepoprawny JSON są odrzucane.
Pojedyncza wiadomość może mieć maksymalnie 1024 bajty.
Współrzędne mogą być ujemne: `x = X modelu`, `y = Z modelu`, w metrach.
Obsługiwany jest również format `{"type":"position","x":1.2,"y":3.4}`.

Jedna kratka mapy ma bok **0,2 m**, a narożnik siatki to `(-106.6, -68.2)`.
Indeks kolumny to `floor((x + 106.6) / 0.2)`, a wiersza
`floor((y + 68.2) / 0.2)`. Środek kratki to
`(-106.6 + (kolumna + 0.5) * 0.2, -68.2 + (wiersz + 0.5) * 0.2)`.
Lokalizację ARKit trzeba wcześniej dopasować do układu modelu.

Potwierdzenie wraca tylko do nadawcy:

```json
{"type":"position","x":1.2,"y":3.4,"receivedAt":"2026-10-10T14:00:00Z"}
```

Przy aktywnym celu po potwierdzeniu pozycji przychodzi także wiadomość
`type: "navigation"` z `nextWaypoint` — punktem przed następną zmianą kierunku.
Wybór celu: `{"type":"destination","x":0.1,"y":-62.3}`.
Anulowanie: `{"type":"cancel"}`. Punkty muszą należeć do dostępnej części mapy,
aby nawigacja mogła wyznaczyć trasę.

`receivedAt` to czas odbioru przez serwer w UTC, nie czas pomiaru lokalizacji.
Błędna wiadomość zwraca `type: "error"` i `code: "INVALID_POSITION"`.
Nie zmienia ostatniej poprawnej pozycji i pozwala wysłać kolejną wiadomość.
Przekroczenie limitu lub wiadomość binarna może zamknąć połączenie.

## Szybki test w przeglądarce

Po ponownym uruchomieniu backendu zaloguj się w Swaggerze. Otwórz konsolę
narzędzi deweloperskich przeglądarki na tej samej stronie i uruchom:

```javascript
const socket = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws/position`);
socket.onmessage = event => console.log(JSON.parse(event.data));
socket.onclose = event => console.log('Zamknięcie połączenia:', event.code);
socket.onopen = () => socket.send(JSON.stringify({ x: 1.2, y: 3.4 }));
```

Po połączeniu wyślij kolejną pozycję:

```javascript
socket.send(JSON.stringify({ x: 1.4, y: 3.6 }));
```

Zamknij po zakończeniu testu: `socket.close()`.
Swagger nie wysyła wiadomości WebSocket bezpośrednio.

## Przechowywanie i dostęp

- Ostatnia pozycja każdego aktywnego połączenia jest w pamięci backendu.
  `PositionStore.latestForUser(email)` udostępnia ostatnią pozycję dla przyszłego
  wyznaczania trasy. Wiele połączeń użytkownika jest obsługiwanych oddzielnie.
- Po zamknięciu połączenia jego pozycja jest usuwana. Restart backendu usuwa
  wszystkie pozycje. Nie zapisujemy historii lokalizacji w PostgreSQL.
- Brak zalogowania powoduje HTTP `401` przy otwieraniu połączenia.
- Sesja jest ponownie sprawdzana przed każdą wiadomością. Po wylogowaniu lub
  wygaśnięciu sesji połączenie jest zamykane kodem `1008`, a jego pozycja usuwana.
  Tomcat może zamknąć je od razu przy unieważnieniu sesji; dodatkowa kontrola
  w handlerze odrzuca następną wiadomość, jeśli połączenie nadal jest otwarte.
- Domyślnie połączenia przeglądarkowe muszą pochodzić z tego samego originu co
  backend. Dla frontendu na osobnym adresie trzeba dodać konkretny zaufany origin
  lub skonfigurować proxy obsługujące WebSocket. Nie dopuszczamy `*`.

Powiązanie z użytkownikiem i kontrola originu korzystają z mechanizmów
[Spring WebSocket](https://docs.spring.io/spring-framework/reference/web/websocket/server.html).

Testy otwierają prawdziwe połączenia HTTP i WebSocket na losowym porcie,
używając oddzielnej bazy H2.
