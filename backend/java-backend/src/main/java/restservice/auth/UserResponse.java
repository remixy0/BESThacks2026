package restservice.auth;

public record UserResponse(Long id, String email, restservice.user.Role role) {}
