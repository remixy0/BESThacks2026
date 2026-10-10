package restservice.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.*;
import restservice.position.PositionHandshakeInterceptor;
import restservice.position.PositionWebSocketHandler;

@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {
    private final PositionWebSocketHandler positions;
    private final PositionHandshakeInterceptor authentication;

    public WebSocketConfig(PositionWebSocketHandler positions, PositionHandshakeInterceptor authentication) {
        this.positions = positions;
        this.authentication = authentication;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        // Keep Spring's same-origin policy; do not allow arbitrary browser origins.
        registry.addHandler(positions, "/ws/position").addInterceptors(authentication);
    }
}
