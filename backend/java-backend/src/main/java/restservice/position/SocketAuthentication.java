package restservice.position;
import jakarta.servlet.http.HttpSession;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.web.context.HttpSessionSecurityContextRepository;
import org.springframework.web.socket.WebSocketSession;
public final class SocketAuthentication {
    private SocketAuthentication() {}
    public static boolean isAuthenticated(WebSocketSession session) {
        if (session.getPrincipal() == null) return false;
        var httpSession = (HttpSession) session.getAttributes().get(PositionHandshakeInterceptor.HTTP_SESSION);
        if (httpSession == null) return false;
        try {
            var stored = httpSession.getAttribute(HttpSessionSecurityContextRepository.SPRING_SECURITY_CONTEXT_KEY);
            if (!(stored instanceof SecurityContext context)) return false;
            var authentication = context.getAuthentication();
            return authentication != null && authentication.isAuthenticated()
                    && authentication.getName().equals(session.getPrincipal().getName());
        } catch (IllegalStateException expiredSession) {
            return false;
        }
    }

    public static boolean isAdmin(WebSocketSession session) {
        if (!isAuthenticated(session)) return false;
        try {
            var http = (HttpSession)session.getAttributes().get(PositionHandshakeInterceptor.HTTP_SESSION);
            var context = (SecurityContext)http.getAttribute(HttpSessionSecurityContextRepository.SPRING_SECURITY_CONTEXT_KEY);
            return context.getAuthentication().getAuthorities().stream().anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"));
        } catch (IllegalStateException expired) { return false; }
    }
}
