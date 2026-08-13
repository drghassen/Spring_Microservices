package org.springboot.userservice.user;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class UserAppTests {

    @Test
    void getAuthoritiesShouldExposeRoleName() {
        var user = UserApp.builder()
                .role(Role.ADMIN)
                .build();

        assertThat(user.getAuthorities())
                .extracting("authority")
                .containsExactly("ADMIN");
    }
}
