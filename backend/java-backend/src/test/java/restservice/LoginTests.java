package restservice;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.test.web.servlet.MockMvc;
import restservice.user.AppUser;
import restservice.user.UserRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(classes = RestServiceApplication.class, properties = {
        "spring.datasource.url=jdbc:h2:mem:login;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.sql.init.mode=never", "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.docker.compose.enabled=false"
})
@AutoConfigureMockMvc
class LoginTests {
    private static final String LOGIN = """
            {"email":" TEST@example.com ","password":"TestoweHaslo123!"}
            """;

    @Autowired MockMvc mvc;
    @Autowired UserRepository users;
    @Autowired PasswordEncoder encoder;

    @BeforeEach
    void createAccount() {
        users.deleteAll();
        users.saveAndFlush(new AppUser("test@example.com", encoder.encode("TestoweHaslo123!")));
    }

    @Test
    void logsInPersistsSessionRotatesSessionIdAndLogsOut() throws Exception {
        var csrf = csrf(null);
        String previousSessionId = csrf.session().getId();
        mvc.perform(post("/api/auth/login").session(csrf.session()).header("X-CSRF-TOKEN", csrf.token())
                        .contentType(MediaType.APPLICATION_JSON).content(LOGIN))
                .andExpect(status().isOk())
                .andExpect(jsonPath("email").value("test@example.com"))
                .andExpect(jsonPath("password").doesNotExist())
                .andExpect(jsonPath("passwordHash").doesNotExist());
        assertThat(csrf.session().getId()).isNotEqualTo(previousSessionId);
        mvc.perform(get("/api/auth/me").session(csrf.session()))
                .andExpect(status().isOk()).andExpect(jsonPath("email").value("test@example.com"));
        // Successful login invalidates the token used by the anonymous session.
        mvc.perform(post("/api/auth/logout").session(csrf.session()).header("X-CSRF-TOKEN", csrf.token()))
                .andExpect(status().isForbidden());
        var loggedInCsrf = csrf(csrf.session());
        mvc.perform(post("/api/auth/logout").session(loggedInCsrf.session())
                        .header("X-CSRF-TOKEN", loggedInCsrf.token()))
                .andExpect(status().isNoContent());
        assertThat(loggedInCsrf.session().isInvalid()).isTrue();
        mvc.perform(get("/api/auth/me")).andExpect(status().isUnauthorized());
    }

    @Test
    void rejectsWrongPasswordAndUnknownEmailWithSameMessage() throws Exception {
        var csrf = csrf(null);
        var wrongPassword = mvc.perform(post("/api/auth/login").session(csrf.session())
                        .header("X-CSRF-TOKEN", csrf.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(LOGIN.replace("TestoweHaslo123!", "NiepoprawneHaslo!")))
                .andExpect(status().isUnauthorized()).andReturn();
        var unknownUser = mvc.perform(post("/api/auth/login").session(csrf.session())
                        .header("X-CSRF-TOKEN", csrf.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(LOGIN.replace("TEST@example.com", "unknown@example.com")))
                .andExpect(status().isUnauthorized()).andReturn();
        assertThat(unknownUser.getResponse().getContentAsString())
                .isEqualTo(wrongPassword.getResponse().getContentAsString());
        mvc.perform(get("/api/auth/me").session(csrf.session())).andExpect(status().isUnauthorized());
    }

    @Test
    void rejectsLoginWithoutCsrfAndCurrentUserWithoutSession() throws Exception {
        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON).content(LOGIN))
                .andExpect(status().isForbidden());
        mvc.perform(get("/api/auth/me")).andExpect(status().isUnauthorized());
    }

    @Test
    void rejectsMultibytePasswordOverBcryptLimit() throws Exception {
        var csrf = csrf(null);
        mvc.perform(post("/api/auth/login").session(csrf.session()).header("X-CSRF-TOKEN", csrf.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(LOGIN.replace("TestoweHaslo123!", "ą".repeat(37))))
                .andExpect(status().isBadRequest());
        mvc.perform(get("/api/auth/me").session(csrf.session())).andExpect(status().isUnauthorized());
    }

    @Test
    void swaggerDescribesCsrfHeaderForLogin() throws Exception {
        mvc.perform(get("/v3/api-docs"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.paths['/api/auth/login'].post.parameters[0].name").value("X-CSRF-TOKEN"));
    }

    private CsrfSession csrf(MockHttpSession session) throws Exception {
        var request = get("/api/auth/csrf");
        if (session != null) {
            request.session(session);
        }
        var result = mvc.perform(request).andExpect(status().isOk())
                .andExpect(jsonPath("headerName").value("X-CSRF-TOKEN"))
                .andExpect(jsonPath("token").isNotEmpty()).andReturn();
        var token = (CsrfToken) result.getRequest().getAttribute(CsrfToken.class.getName());
        return new CsrfSession((MockHttpSession) result.getRequest().getSession(), token.getToken());
    }

    private record CsrfSession(MockHttpSession session, String token) {}
}
