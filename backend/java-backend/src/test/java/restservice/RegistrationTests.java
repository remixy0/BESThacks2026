package restservice;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import restservice.user.UserRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(classes = RestServiceApplication.class, properties = {
        "spring.datasource.url=jdbc:h2:mem:registration;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.sql.init.mode=never", "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.docker.compose.enabled=false"
})
@AutoConfigureMockMvc
class RegistrationTests {
    @Autowired MockMvc mvc;
    @Autowired UserRepository users;
    @Autowired PasswordEncoder passwordEncoder;

    @BeforeEach
    void clearUsers() {
        users.deleteAll();
    }

    @Test
    void registersNormalizesEmailAndStoresOnlyPasswordHash() throws Exception {
        mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":" Test@Example.com ","password":"TestoweHaslo123!"}
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("id").isNumber())
                .andExpect(jsonPath("email").value("test@example.com"))
                .andExpect(jsonPath("password").doesNotExist())
                .andExpect(jsonPath("passwordHash").doesNotExist());
        var user = users.findByEmail("test@example.com").orElseThrow();
        assertThat(user.getPasswordHash()).isNotEqualTo("TestoweHaslo123!");
        assertThat(passwordEncoder.matches("TestoweHaslo123!", user.getPasswordHash())).isTrue();
    }

    @Test
    void rejectsDuplicateEmailIgnoringCase() throws Exception {
        String body = """
                {"email":"test@example.com","password":"TestoweHaslo123!"}
                """;
        mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated());
        mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                        .content(body.replace("test@example.com", "TEST@example.com")))
                .andExpect(status().isConflict());
        assertThat(users.count()).isEqualTo(1);
    }

    @Test
    void rejectsInvalidEmailAndShortPassword() throws Exception {
        mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"niepoprawny","password":"TestoweHaslo123!"}
                                """))
                .andExpect(status().isBadRequest());
        mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"test@example.com","password":"123"}
                                """))
                .andExpect(status().isBadRequest());
        assertThat(users.count()).isZero();
    }

    @Test
    void rejectsPasswordExceedingBcryptByteLimit() throws Exception {
        mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"test@example.com\",\"password\":\"" + "ą".repeat(37) + "\"}"))
                .andExpect(status().isBadRequest());
        assertThat(users.count()).isZero();
    }
}
