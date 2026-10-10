package restservice.auth;

import jakarta.validation.Valid;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.enums.ParameterIn;
import io.swagger.v3.oas.annotations.Operation;
import org.springframework.http.HttpStatus;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.web.authentication.logout.SecurityContextLogoutHandler;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final RegistrationService registration;
    private final LoginService login;

    public AuthController(RegistrationService registration, LoginService login) {
        this.registration = registration;
        this.login = login;
    }

    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    public UserResponse register(@Valid @RequestBody RegisterRequest request) {
        return registration.register(request);
    }

    @GetMapping("/csrf")
    @Operation(summary = "Pobierz token CSRF przed logowaniem lub wylogowaniem")
    public ResponseEntity<CsrfResponse> csrf(CsrfToken token) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(new CsrfResponse(token.getHeaderName(), token.getToken()));
    }

    @PostMapping("/login")
    @Operation(summary = "Zaloguj użytkownika i zapisz sesję",
            parameters = @Parameter(name = "X-CSRF-TOKEN", in = ParameterIn.HEADER, required = true,
                    description = "Token z GET /api/auth/csrf"))
    public ResponseEntity<UserResponse> login(@Valid @RequestBody LoginRequest credentials,
                                              HttpServletRequest request, HttpServletResponse response) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(login.login(credentials, request, response));
    }

    @GetMapping("/me")
    @Operation(summary = "Sprawdź aktualnie zalogowanego użytkownika")
    public ResponseEntity<UserResponse> me(Authentication authentication) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(login.currentUser(authentication));
    }

    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "Wyloguj użytkownika i unieważnij sesję",
            parameters = @Parameter(name = "X-CSRF-TOKEN", in = ParameterIn.HEADER, required = true,
                    description = "Świeży token z GET /api/auth/csrf pobrany po logowaniu"))
    public void logout(HttpServletRequest request, HttpServletResponse response, Authentication authentication) {
        new SecurityContextLogoutHandler().logout(request, response, authentication);
    }

    public record CsrfResponse(String headerName, String token) {}
}
