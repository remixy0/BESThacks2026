# PostgreSQL — konfiguracja lokalna

Połączenie w zakładce Database w IntelliJ jest niezależne od połączenia aplikacji.
Baza musi już istnieć i serwer PostgreSQL musi być uruchomiony.

W IntelliJ otwórz Run → Edit Configurations → konfiguracja
RestServiceApplication → Environment variables i ustaw:

```text
DB_URL=jdbc:postgresql://localhost:5432/nazwa_bazy
DB_USER=twoj_uzytkownik
DB_PASSWORD=twoje_haslo
```

Użyj hosta, portu, nazwy bazy i danych użytkownika z działającego połączenia
w zakładce Database. Nie zapisuj prawdziwego hasła w plikach repozytorium.

Uruchom klasę `restservice.RestServiceApplication`. Przy starcie Spring Boot
wykona `src/main/resources/schema.sql`, tworząc tabelę `app_users`, jeśli jeszcze
nie istnieje. Użytkownik bazy musi mieć uprawnienie do tworzenia tabel w używanym
schemacie. Skrypt nie aktualizuje struktury już istniejącej tabeli.

Tabela przechowuje identyfikator, unikalny e-mail, hash hasła i datę utworzenia.
Kod rejestracji powinien normalizować e-mail do małych liter oraz hashować hasło
przed zapisaniem. Nie zapisuj hasła jawnym tekstem.

Rejestracja jest dostępna przez `POST /api/auth/register`. Po przeładowaniu
projektu Maven i ponownym uruchomieniu aplikacji otwórz
`http://localhost:8080/swagger-ui/index.html`, wybierz endpoint rejestracji,
kliknij **Try it out** i wyślij:

```json
{
  "email": "test@example.com",
  "password": "TestoweHaslo123!"
}
```

Oczekiwane wyniki: `201 Created` dla nowego konta, `409 Conflict` dla zajętego
e-maila i `400 Bad Request` dla niepoprawnych danych. E-mail jest zapisywany
małymi literami, a hasło jako hash BCrypt. Hasło musi mieć od 8 do 72 znaków
i nie więcej niż 72 bajty UTF-8. Możesz też uruchomić przykłady z pliku
`registration.http` za pomocą klienta HTTP w IntelliJ.

W pgAdmin sprawdź zapis:

```sql
SELECT id, email, created_at FROM app_users;
```

Rejestracja nie loguje użytkownika. Logowanie, sprawdzanie bieżącego
użytkownika i wylogowanie są opisane w `AUTH.md`. Uwierzytelnianie używa sesji.
Adresy API poza endpointami konta są obecnie zablokowane przez Spring Security.
Testy rejestracji używają osobnej bazy H2 w pamięci i nie zmieniają PostgreSQL.

Przy dalszym rozwijaniu struktury przenieś zarządzanie schematem do migracji
Flyway i wyłącz `spring.sql.init.mode=always`.

Integracja Spring Boot z Docker Compose jest wyłączona, ponieważ obecny
`compose.yaml` nie definiuje żadnych usług, a połączenie wskazuje osobno
uruchomiony serwer PostgreSQL.
