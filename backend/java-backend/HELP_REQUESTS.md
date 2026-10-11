# Zgłoszenia pomocy — aplikacja i panel webowy

Użytkownik naciska przycisk „Potrzebuję pomocy” w aplikacji. Backend przyjmuje zgłoszenie
przez istniejący WebSocket użytkownika i wysyła je do wszystkich aktualnie połączonych
paneli administratorów. Nie trzeba otwierać dodatkowego połączenia ani wywoływać REST API.

## Połączenia i autoryzacja

| Strona | WebSocket lokalnie | Rola |
|---|---|---|
| Aplikacja użytkownika | `ws://localhost:8081/ws/position` | `USER` lub `ADMIN` |
| Panel webowy administratora | `ws://localhost:8081/ws/admin` | `ADMIN` |

Najpierw zaloguj się przez `/api/auth/login`; handshake WebSocket musi korzystać
z cookie tej samej sesji. Na produkcji z HTTPS używaj `wss://`.
Szczegóły logowania, CSRF i cookie dla iOS: [INTEGRATION.md](INTEGRATION.md).
Zgłoszenia otrzymują wyłącznie administratorzy, nie inni użytkownicy.
Po wylogowaniu lub wygaśnięciu sesji połączenie jest zamykane kodem `1008`.

## 1. Aplikacja wysyła zgłoszenie

Najprostszy komunikat:

```json
{"type":"help"}
```

Backend dołącza ostatnią pozycję otrzymaną przez **to samo połączenie** `/ws/position`.
Nie korzysta z pozycji innych urządzeń zalogowanych na to samo konto.
Jeśli nie otrzymał jeszcze pozycji, przekaże `position: null`; zgłoszenie nadal zostanie przyjęte.

Można też dołączyć aktualną lokalizację bez wcześniejszego komunikatu `position`:

```json
{"type":"help","x":-0.5,"y":51.9}
```

`x` i `y` muszą wystąpić razem i być skończonymi liczbami JSON.
Współrzędne są w **metrach, w układzie aktualnej mapy**, tak samo jak przy nawigacji.
Backend nie wymaga, aby zgłoszona pozycja znajdowała się w przechodniej kratce mapy.
Te współrzędne stanowią tylko lokalizację zgłoszenia: nie aktualizują `positions`
ani nie zmieniają celu lub trasy użytkownika. Zwykłe aktualizacje pozycji wysyłaj dalej osobno.

Nie przesyłaj emaila, identyfikatora użytkownika ani czasu. Backend ustala tożsamość
z zalogowanej sesji i sam nadaje identyfikator oraz czas przyjęcia. Dodatkowe pola są odrzucane.

## 2. Aplikacja otrzymuje potwierdzenie

```json
{
  "type":"help.accepted",
  "id":"f6cc263c-5dd3-4ea0-af92-03e73160bd12",
  "receivedAt":"2026-10-11T01:00:00Z"
}
```

| Pole | Znaczenie |
|---|---|
| `type` | Zawsze `help.accepted` |
| `id` | UUID nadany przez backend dla tego zgłoszenia |
| `receivedAt` | Czas przyjęcia przez backend, ISO 8601 UTC |

Potwierdzenie oznacza **przyjęcie przez backend**, nie przeczytanie przez administratora
ani udzielenie pomocy. Aplikacja może wyświetlić „Zgłoszenie przyjęte przez system”.
Nie wyświetlaj na tej podstawie „Pomoc jest w drodze”.

## 3. Panel webowy otrzymuje zdarzenie

Na `/ws/admin` pojawia się nowy typ komunikatu:

```json
{
  "type":"help.request",
  "id":"f6cc263c-5dd3-4ea0-af92-03e73160bd12",
  "username":"user@example.com",
  "position":{"x":-0.5,"y":51.9},
  "receivedAt":"2026-10-11T01:00:00Z"
}
```

| Pole | Znaczenie |
|---|---|
| `type` | Zawsze `help.request` |
| `id` | Ten sam UUID, który otrzymuje aplikacja |
| `username` | Email zalogowanego użytkownika, ustalony przez backend |
| `position` | `{x, y}` w metrach albo `null`, gdy brak lokalizacji |
| `receivedAt` | Ten sam czas przyjęcia, który otrzymuje aplikacja |

Panel powinien dodać zgłoszenie do listy i wyróżnić je na mapie, jeśli `position` nie jest `null`.
Brak lokalizacji powinien być opisany jako „Lokalizacja nieznana”. Pozycja jest zapisem
z chwili zgłoszenia i nie aktualizuje się w nim automatycznie; bieżącą pozycję użytkownika
panel nadal otrzymuje przez komunikaty `positions`.

Przykład obsługi w istniejącym panelu JavaScript:

```javascript
// adminSocket to istniejące, zalogowane połączenie /ws/admin.
adminSocket.addEventListener("message", ({ data }) => {
  const event = JSON.parse(data);
  if (event.type !== "help.request") return;

  // Dodaj obsługę UI do istniejącego dispatchera komunikatów.
  console.log("Zgłoszenie pomocy:", event.id, event.username);
  if (event.position !== null) {
    console.log("Pozycja na mapie:", event.position.x, event.position.y);
  }
});
```

## Błędy i ponawianie

Niepoprawne pola zgłoszenia, np. brak `y`, tekstowe `x`, nieskończona liczba lub
dodatkowe `username`, dają odpowiedź na `/ws/position`:

```json
{
  "type":"error",
  "code":"INVALID_HELP",
  "message":"Wyślij type: help, opcjonalnie skończone x i y w metrach."
}
```

Niepoprawny JSON jest obsługiwany przez istniejący parser i daje `INVALID_POSITION`.
Błąd komunikatu nie zamyka połączenia; można poprawić dane i spróbować ponownie.
Każdy poprawny komunikat `help` tworzy nowe zgłoszenie i nowy UUID. Nie ma deduplikacji
ani limitu częstotliwości: aplikacja powinna blokować wielokrotne kliknięcia podczas oczekiwania
na potwierdzenie. Brak potwierdzenia po utracie połączenia nie pozwala ustalić, czy zgłoszenie
dotarło — ponowienie może stworzyć drugie zgłoszenie.

## Zakres obecnej implementacji

- Zgłoszenia są przekazywane **na żywo** do administratorów z aktywną sesją i WebSocketem.
- Nie są zapisywane w PostgreSQL, kolejkowane ani odtwarzane po ponownym połączeniu.
- Gdy żaden administrator nie jest podłączony, backend nadal zwróci `help.accepted`,
  ale panel po późniejszym połączeniu nie otrzyma wcześniejszego zgłoszenia.
- Komenda administratora `snapshot` zwraca istniejące polityki i pozycje, bez historii zgłoszeń.
- Nie ma jeszcze komendy potwierdzania, zamykania ani anulowania zgłoszenia.
- Zgłoszenie pomocy nie włącza alarmu ewakuacyjnego i nie zmienia nawigacji.
- Jak przy obecnym systemie pozycji i alarmów, uruchamiaj jedną instancję backendu.

## Szybki test integracji

1. Zaloguj administratora i otwórz `/ws/admin` z jego cookie sesji.
2. Zaloguj użytkownika w aplikacji i otwórz `/ws/position` z jego cookie sesji.
3. Wyślij `{"type":"help","x":-0.5,"y":51.9}` z aplikacji.
4. Aplikacja powinna dostać `help.accepted`, a panel `help.request` z tym samym `id`.
5. Wyślij zwykłą pozycję, a potem `{"type":"help"}` i sprawdź wykorzystanie ostatniej pozycji.
6. Na nowym połączeniu bez pozycji wyślij `{"type":"help"}` i sprawdź `position: null` w panelu.
