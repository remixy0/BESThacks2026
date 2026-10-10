# Logowanie przez sesję

Uruchom ponownie `RestServiceApplication` i odśwież Swagger:
`http://localhost:8081/swagger-ui/index.html` (lub port ustawiony w aplikacji).

## Sprawdzenie w Swaggerze

1. Wykonaj **GET /api/auth/csrf** przez **Try it out → Execute**.
   Skopiuj wartość pola `token` z odpowiedzi, bez cudzysłowów.
   Przeglądarka zachowa ciasteczko sesji.
2. Otwórz **POST /api/auth/login**, kliknij **Try it out** i w polu
   nagłówka **X-CSRF-TOKEN** wklej skopiowany token.
   W body podaj dane zarejestrowanego konta:

   ```json
   {
     "email": "test@example.com",
     "password": "TestoweHaslo123!"
   }
   ```

   Wynik **200 OK** zawiera identyfikator i e-mail użytkownika.
   Błędny e-mail lub hasło zwraca **401 Unauthorized** z takim samym komunikatem.
3. Wykonaj **GET /api/auth/me** w tej samej przeglądarce.
   **200 OK** i dane konta potwierdzają, że sesja jest zapamiętana.
4. Pobierz ponownie **GET /api/auth/csrf** — logowanie zmienia token.
   Użyj świeżego tokenu w polu **X-CSRF-TOKEN** przy **POST /api/auth/logout**.
   Wylogowanie zwraca **204 No Content** i unieważnia sesję.
5. Kolejne **GET /api/auth/me** zwróci **401 Unauthorized**.

**403 Forbidden** przy logowaniu lub wylogowaniu zwykle oznacza brak tokenu
CSRF albo token ze starej lub innej sesji. Pobierz go ponownie z `/api/auth/csrf`.

## Dla frontendu

Używaj tego samego hosta dla wszystkich wywołań (nie mieszaj `localhost` z
`127.0.0.1`). Przy wywołaniach fetch wysyłaj ciasteczka przez
`credentials: 'include'`. Token pobieraj przed logowaniem i ponownie po
logowaniu; dodawaj go w nagłówku `X-CSRF-TOKEN` do żądań zmieniających dane.
Rejestracja pozostaje publiczna i nie wymaga tego tokenu, ponieważ nie loguje.

Jeżeli frontend działa na innym originie, konfiguracja CORS wymaga ustawienia
konkretnego adresu frontendu oraz zezwolenia na ciasteczka. Nie jest jeszcze
dodana, ponieważ adres frontendu nie został ustalony. Lokalnie można użyć
proxy frontendu do backendu, tak aby przeglądarka widziała ten sam origin.

Sesja wygasa po 30 minutach bezczynności, po wylogowaniu lub restarcie backendu.
Ciasteczko jest `HttpOnly`, `SameSite=Lax`; przed wdrożeniem przez HTTPS ustaw
`server.servlet.session.cookie.secure=true`. Sesje są obecnie przechowywane
w pamięci pojedynczej instancji backendu.

Implementacja zapisuje kontekst logowania i zmienia identyfikator sesji oraz
token CSRF po logowaniu, zgodnie z mechanizmami
[Spring Security](https://docs.spring.io/spring-security/reference/servlet/authentication/session-management.html).

Testy używają osobnej bazy H2 i nie zmieniają danych PostgreSQL.
