package restservice.auth;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.session.SessionAuthenticationStrategy;
import org.springframework.security.web.context.SecurityContextRepository;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import restservice.user.UserRepository;
import java.nio.charset.StandardCharsets;

@Service
public class LoginService {
    private final AuthenticationManager authenticationManager;
    private final SecurityContextRepository contexts;
    private final SessionAuthenticationStrategy sessions;
    private final UserRepository users;

    public LoginService(AuthenticationManager authenticationManager, SecurityContextRepository contexts,
                        SessionAuthenticationStrategy sessions, UserRepository users) {
        this.authenticationManager = authenticationManager;
        this.contexts = contexts;
        this.sessions = sessions;
        this.users = users;
    }

    public UserResponse login(LoginRequest credentials, HttpServletRequest request, HttpServletResponse response) {
        if (credentials.password().getBytes(StandardCharsets.UTF_8).length > 72) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Hasło przekracza 72 bajty UTF-8.");
        }
        Authentication authentication = authenticationManager.authenticate(
                UsernamePasswordAuthenticationToken.unauthenticated(credentials.email(), credentials.password()));
        UserResponse user = currentUser(authentication);
        // Rotate the session ID and CSRF token after successful authentication.
        sessions.onAuthentication(authentication, request, response);
        var context = SecurityContextHolder.createEmptyContext();
        context.setAuthentication(authentication);
        SecurityContextHolder.setContext(context);
        contexts.saveContext(context, request, response);
        return user;
    }

    public UserResponse currentUser(Authentication authentication) {
        var user = users.findByEmail(authentication.getName())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                        "Użytkownik nie istnieje."));
        return new UserResponse(user.getId(), user.getEmail());
    }
}
