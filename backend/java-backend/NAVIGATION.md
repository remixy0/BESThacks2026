# Nawigacja po punktach zmiany kierunku

Połączenie: `ws://localhost:8081/ws/position`. Wymaga istniejącej sesji
logowania; sposób połączenia i ciasteczka opisano w `AUTH.md` i `WEBSOCKET.md`.
Nawigacja jest przypisana do pojedynczego połączenia. Po ponownym połączeniu
wyślij aktualną pozycję oraz cel jeszcze raz.

## Aktualna mapa

Backend korzysta z podmienionego pliku `src/main/resources/maps/field-museum-main-level.grid.json`.
Układ współrzędnych pozostaje taki sam: metry, kratki 0,2 m, początek siatki
`(-106.6, -68.2)`, rozmiar 1066 × 681. Nowy sugerowany start to `(0.1, 55.9)`.
Mapa zawiera już bufor 1 m dla środków przechodnich komórek przy przeszkodach.
Margines 0,3 m dla dynamicznych stref administratora pozostaje bez zmian.

Aplikacja powinna używać nowego pliku mapy i współrzędnych `pointsOfInterest[].approach`
do wyboru celów; część starych punktów znajduje się teraz w zablokowanych komórkach.
Dostępne są 24 punkty z 25. Pawnee Earth Lodge i Mastaba mają teraz dostępne punkty
podejścia, natomiast punkt `restroom` ma `approach: null` i nie powinien być wybierany
jako cel. Wyjścia używane przez alarm to `(0.3, 59.9)` oraz `(0.1, -61.9)`.
Identyfikator mapy i format wiadomości WebSocket pozostają bez zmian.
Po podmianie pliku należy zrestartować backend, ponieważ ładuje mapę przy uruchomieniu.

## Wiadomości aplikacji

Aktualna pozycja w metrach, w układzie mapy:

```json
{"type":"position","x":-0.5,"y":51.9}
```

Poprzedni format `{"x":-0.5,"y":51.9}` nadal działa.

Wybrany cel — tutaj dostępny punkt przy północnym wejściu z pliku mapy:

```json
{"type":"destination","x":0.1,"y":-61.9}
```

Cel można przesłać przed pozycją; serwer odpowie `awaiting_position`.
Nowy poprawny cel zastępuje poprzedni i powoduje przeliczenie trasy.
Niepoprawny cel (np. ściana) zwraca błąd i nie zmienia poprzedniego celu.
Jeśli aplikacja chce go również usunąć, powinna wysłać `cancel`.

Anulowanie prowadzenia:

```json
{"type":"cancel"}
```

Współrzędne muszą być skończonymi liczbami JSON. Pola dodatkowe i identyfikator
innego użytkownika nie są przyjmowane. Nadal obowiązuje limit 1024 bajtów.

## Odpowiedź i kolejne punkty

Pozycja zawsze otrzymuje dotychczasowe potwierdzenie `type: "position"`.
Jeśli wybrano cel, po nim przychodzi osobna wiadomość `type: "navigation"`.
Wybór celu i anulowanie zwracają od razu wiadomość nawigacji.

| Pole | Znaczenie |
|---|---|
| `type` | Zawsze `navigation` |
| `status` | `awaiting_position`, `navigating`, `arrived`, `blocked`, `cancelled` |
| `mapId` | `field-museum-main-level` |
| `routeId` | Identyfikator wyznaczonej trasy; zmienia się przy przeliczeniu |
| `destination` | Dokładne współrzędne celu wskazane przez aplikację |
| `nextWaypoint` | `{x, y}` następnego zakrętu lub celu; `null`, gdy brak prowadzenia |
| `waypointIndex` | Indeks punktu od zera; `null`, gdy brak prowadzenia |
| `waypointCount` | Liczba punktów po uproszczeniu, bez pozycji startowej |
| `distanceToWaypointM` | Odległość od aktualnej pozycji do następnego punktu |
| `remainingDistanceM` | Pozostała długość łamanej; `0` przy dotarciu, `null`, gdy nieznana |
| `recalculated` | Czy dla tej aktualizacji wyznaczono nową trasę |
| `reason` | Kod problemu przy `blocked`; w pozostałych przypadkach `null` |
| `waypointToleranceM` | Domyślnie `0.4` m |
| `arrivalToleranceM` | Domyślnie `0.3` m |

Frontend kieruje osobę do **`nextWaypoint`**, a nie do sąsiedniej kratki.
Punkt jest końcem bezpiecznego prostego odcinka. Odcinek może być ukośny i mieć
dowolny kąt. Serwer nie przesyła setek punktów siatki.

Przy kolejnych aktualizacjach na prostej `nextWaypoint` i `routeId` pozostają
takie same. Aktualizują się odległości. Nie trzeba animować nowej strzałki tylko
dlatego, że ponownie otrzymano ten sam punkt.

Po dojściu w promień 40 cm od zakrętu serwer przełącza na kolejny punkt **tylko
jeśli bezpośredni odcinek do niego jest wolny**. Rozpoznaje też pozycję na
następnym odcinku, gdy aktualizacja ominęła sam zakręt. Takie przejście nie
zmienia `routeId`. Ostatni punkt ma dokładne współrzędne celu, a nie zaokrąglony
środek komórki.

Dotarcie w promień 30 cm od celu przy wolnym odcinku do niego daje `arrived`,
`nextWaypoint: null` i `remainingDistanceM: 0`. To stan końcowy do wskazania
nowego celu lub anulowania.

## Błędy i zejście z trasy

- Odchylenie o ponad **0,75 m** od bieżącego odcinka lub utrata widoczności
  następnego punktu powoduje przeliczenie trasy od aktualnej pozycji.
- Pozycja w przeszkodzie/poza mapą daje `status: "blocked"`, `nextWaypoint: null`
  oraz `reason: "POSITION_BLOCKED"` lub `POSITION_OUTSIDE_MAP`. Aplikacja powinna
  wstrzymać prowadzenie i usunąć poprzednią strzałkę. Kolejna poprawna pozycja
  wznawia wyznaczanie trasy do zapamiętanego celu.
- Brak połączenia z celem daje `blocked` z powodem `NO_ROUTE`.
- Niepoprawny wybór celu daje `type: "error"` z kodem `DESTINATION_BLOCKED`
  albo `DESTINATION_OUTSIDE_MAP`. Dotychczasowa trasa pozostaje aktywna.
- Błędne dane wiadomości dają `INVALID_POSITION` (kod zachowany dla zgodności
  z poprzednim klientem); nieznany typ daje `UNSUPPORTED_MESSAGE`.
- Wylogowanie, zamknięcie połączenia i błąd transportu usuwają stan nawigacji.

Pozycje i cele nie są automatycznie przesuwane na wolną kratkę, ponieważ takie
przesunięcie mogłoby przenieść użytkownika na drugą stronę ściany. Jeżeli celem
jest eksponat, wybierz jego **`approach`** z mapy, a nie środek eksponatu.

## Szybki test

Uruchom ponownie backend, zaloguj się w Swaggerze i w konsoli przeglądarki
na stronie backendu wykonaj:

```javascript
var socket = new WebSocket(`ws://${location.host}/ws/position`);
var guidance = null;

socket.onmessage = event => {
  const message = JSON.parse(event.data);
  console.log(message);
  if (message.type === "navigation") {
    guidance = message;
    if (message.status === "navigating") {
      console.log("Kieruj do:", message.nextWaypoint);
    }
  }
};

socket.onopen = () => {
  socket.send(JSON.stringify({type: "position", x: -0.5, y: 51.9}));
  socket.send(JSON.stringify({type: "destination", x: 0.1, y: -61.9}));
};
```

Wyłącznie do symulacji testowej: po otrzymaniu odpowiedzi można zasymulować
dojście do wskazanego zakrętu i zobaczyć następny punkt:

```javascript
if (guidance?.status === "navigating") {
  socket.send(JSON.stringify({type: "position", ...guidance.nextWaypoint}));
}
```

W aplikacji iOS wysyłaj rzeczywiście zmierzoną pozycję przeliczoną do układu
modelu, nie tę symulację. Kolejność wiadomości na jednym WebSockecie wyznacza
kolejność aktualizacji. Backend nie interpoluje ruchu w czasie braku danych.

## Algorytm

Mapa jest ładowana raz z zasobów aplikacji. Przechodnie są wyłącznie komórki
`'1'`; ich istniejący margines dla pieszego jest zachowany.

1. Sprawdzenie dostępności pozycji i celu (również granic komórek).
2. Jeśli cały prosty odcinek jest wolny, jedynym punktem zostaje cel.
3. W przeciwnym przypadku A* po czterech sąsiadach z heurystyką Manhattan.
4. Uproszczenie metodą widoczności: od bieżącego punktu wybrany zostaje
   najdalszy widoczny punkt na znalezionej trasie, aż do celu.
5. Każdy skrót sprawdzany jest przez przejście po wszystkich komórkach
   dotykanych odcinkiem (supercover). Niedozwolone jest cięcie narożników
   ani przesuwanie się dokładnie po krawędzi zablokowanej komórki.

Algorytm wyznacza bezpieczną uproszczoną trasę. Nie gwarantuje globalnie
najkrótszej trasy w ciągłej przestrzeni przy dowolnych kątach.
Progi 0,4/0,3/0,75 m są stałymi w `NavigationService` i można je dostroić do
dokładności lokalizacji telefonu.


Role USER/ADMIN, WebSocket administratora, alarm i dynamiczne strefy: [ADMIN.md](ADMIN.md).
