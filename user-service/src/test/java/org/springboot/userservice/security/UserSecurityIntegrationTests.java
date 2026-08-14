package org.springboot.userservice.security;

import org.junit.jupiter.api.Test;
import org.springboot.userservice.library.LibraryClient;
import org.springboot.userservice.repository.UserRepo;
import org.springboot.userservice.services.JwtService;
import org.springboot.userservice.user.Role;
import org.springboot.userservice.user.UserApp;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Optional;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "spring.cloud.config.enabled=false",
        "eureka.client.enabled=false",
        "uploads.dir=target/test-uploads",
        "jwt.secret=413F4428472B4BB6250655368566D5970337336763979244226452948404D6351"
})
@AutoConfigureMockMvc
class UserSecurityIntegrationTests {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JwtService jwtService;

    @MockitoBean
    private UserRepo userRepo;

    @MockitoBean
    private LibraryClient libraryClient;

    @Test
    void shouldRejectAdminEndpointWithoutJwt() throws Exception {
        mockMvc.perform(get("/api/v1/user/admin"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void shouldForbidAdminEndpointForUserRole() throws Exception {
        UserApp user = user("alice", "user-id", Role.USER);

        mockMvc.perform(get("/api/v1/user/admin")
                        .header(HttpHeaders.AUTHORIZATION, bearerTokenFor(user)))
                .andExpect(status().isForbidden());
    }

    @Test
    void shouldAllowAdminEndpointForAdminAndNeverSerializePassword() throws Exception {
        UserApp admin = user("admin", "admin-id", Role.ADMIN);
        admin.setPassword("bcrypt-hash-must-never-be-in-the-response");

        when(userRepo.findAll()).thenReturn(List.of(admin));

        mockMvc.perform(get("/api/v1/user/admin")
                        .header(HttpHeaders.AUTHORIZATION, bearerTokenFor(admin)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].username").value("admin"))
                .andExpect(jsonPath("$[0].password").doesNotExist());
    }

    @Test
    void shouldAllowAUserToReadOnlyTheirOwnProfile() throws Exception {
        UserApp alice = user("alice", "alice-id", Role.USER);

        mockMvc.perform(get("/api/v1/users/username/alice")
                        .header(HttpHeaders.AUTHORIZATION, bearerTokenFor(alice)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("alice"))
                .andExpect(jsonPath("$.password").doesNotExist());
    }

    @Test
    void shouldForbidAUserFromReadingAnotherUsersProfile() throws Exception {
        UserApp alice = user("alice", "alice-id", Role.USER);

        mockMvc.perform(get("/api/v1/users/username/bob")
                        .header(HttpHeaders.AUTHORIZATION, bearerTokenFor(alice)))
                .andExpect(status().isForbidden());
    }

    @Test
    void shouldRejectATokenForADeletedAccount() throws Exception {
        UserApp deletedUser = user("deleted-user", "deleted-id", Role.USER);
        when(userRepo.findByUsername(deletedUser.getUsername())).thenReturn(Optional.empty());

        mockMvc.perform(get("/api/v1/user/admin")
                        .header(HttpHeaders.AUTHORIZATION,
                                "Bearer " + jwtService.generateToken(deletedUser)))
                .andExpect(status().isUnauthorized());
    }

    private String bearerTokenFor(UserApp user) {
        when(userRepo.findByUsername(user.getUsername())).thenReturn(Optional.of(user));
        return "Bearer " + jwtService.generateToken(user);
    }

    private UserApp user(String username, String id, Role role) {
        return UserApp.builder()
                .id(id)
                .name(username)
                .username(username)
                .email(username + "@example.test")
                .address("Test address")
                .password("bcrypt-hash")
                .role(role)
                .build();
    }
}
