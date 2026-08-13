package org.springboot.userservice.mapper;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springboot.userservice.request.UserRequest;
import org.springboot.userservice.user.Role;
import org.springboot.userservice.user.UserApp;
import org.springframework.security.crypto.password.PasswordEncoder;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UserMapperTests {

    @Mock
    private PasswordEncoder passwordEncoder;

    @Test
    void toUserShouldMapFieldsAndEncodePassword() {
        when(passwordEncoder.encode("secret")).thenReturn("encoded-secret");

        var mapper = new UserMapper(passwordEncoder);
        var request = new UserRequest(
                "id-1",
                "Jane Doe",
                "jane@example.com",
                "jane",
                "secret",
                "12 Main St"
        );

        UserApp result = mapper.toUser(request);

        assertThat(result).isNotNull();
        assertThat(result.getId()).isEqualTo("id-1");
        assertThat(result.getName()).isEqualTo("Jane Doe");
        assertThat(result.getUsername()).isEqualTo("jane");
        assertThat(result.getEmail()).isEqualTo("jane@example.com");
        assertThat(result.getAddress()).isEqualTo("12 Main St");
        assertThat(result.getPassword()).isEqualTo("encoded-secret");
        assertThat(result.getRole()).isEqualTo(Role.USER);
    }

    @Test
    void toUserShouldReturnNullWhenRequestIsNull() {
        var mapper = new UserMapper(passwordEncoder);

        assertThat(mapper.toUser(null)).isNull();
    }
}
