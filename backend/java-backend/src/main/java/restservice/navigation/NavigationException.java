package restservice.navigation;

public class NavigationException extends RuntimeException {
    private final String code;

    public NavigationException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String code() { return code; }
}
