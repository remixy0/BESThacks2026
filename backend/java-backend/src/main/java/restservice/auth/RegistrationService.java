package restservice.auth;

import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import restservice.user.AppUser;
import restservice.user.UserRepository;
import java.nio.charset.StandardCharsets;

@Service
public class RegistrationService {
    private final UserRepository users;
    private final PasswordEncoder passwordEncoder;

    public RegistrationService(UserRepository users, PasswordEncoder passwordEncoder) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
    }

    public UserResponse register(RegisterRequest request) {
        // BCrypt limits passwords by UTF-8 bytes, not by character count.
        if (request.password().getBytes(StandardCharsets.UTF_8).length > 72) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Hasło może mieć maksymalnie 72 bajty UTF-8.");
        }
        if (users.existsByEmail(request.email())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Konto z tym adresem e-mail już istnieje.");
        }
        AppUser user = users.saveAndFlush(new AppUser(
                request.email(), passwordEncoder.encode(request.password())));
        return new UserResponse(user.getId(), user.getEmail());
    }
}
