package restservice.auth;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.*;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.security.core.AuthenticationException;

@RestControllerAdvice(assignableTypes = AuthController.class)
public class AuthExceptionHandler {
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ProblemDetail> invalidRequest() {
        return problem(HttpStatus.BAD_REQUEST,
                "Niepoprawne dane. Podaj poprawny e-mail i hasło zgodne z wymaganiami endpointu.");
    }

    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<ProblemDetail> authenticationFailed() {
        return problem(HttpStatus.UNAUTHORIZED, "Niepoprawny e-mail lub hasło.");
    }

    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<ProblemDetail> rejectedRequest(ResponseStatusException exception) {
        return problem(exception.getStatusCode(), exception.getReason());
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ProblemDetail> dataConflict(DataIntegrityViolationException exception) {
        // The unique constraint also protects simultaneous registration requests.
        for (Throwable cause = exception; cause != null; cause = cause.getCause()) {
            if (cause instanceof org.hibernate.exception.ConstraintViolationException violation
                    && "app_users_email_key".equalsIgnoreCase(violation.getConstraintName())) {
                return problem(HttpStatus.CONFLICT, "Konto z tym adresem e-mail już istnieje.");
            }
        }
        return problem(HttpStatus.INTERNAL_SERVER_ERROR, "Nie udało się zapisać konta.");
    }

    private ResponseEntity<ProblemDetail> problem(HttpStatusCode status, String detail) {
        return ResponseEntity.status(status).body(ProblemDetail.forStatusAndDetail(status, detail));
    }
}
