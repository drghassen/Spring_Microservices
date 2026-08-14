package org.springboot.userservice.services;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;

import java.security.Key;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(properties = {
        "spring.cloud.config.enabled=false",
        "eureka.client.enabled=false",
        "uploads.dir=target/test-uploads",
        "jwt.secret=413F4428472B4BB6250655368566D5970337336763979244226452948404D6351"
})
class JwtServiceTests {

    @Autowired
    private JwtService jwtService;

    @Test
    void generateTokenShouldEmbedUsernameAndRoles() {
        UserDetails userDetails = User.withUsername("john")
                .password("password")
                .roles("USER", "ADMIN")
                .build();

        String token = jwtService.generateToken(userDetails);
        var claims = Jwts.parserBuilder()
                .setSigningKey(getSigningKey())
                .build()
                .parseClaimsJws(token)
                .getBody();

        assertThat(claims.getSubject()).isEqualTo("john");
        assertThat(claims.get("roles", List.class)).containsExactlyInAnyOrder("ROLE_USER", "ROLE_ADMIN");
    }

    private Key getSigningKey() {
        byte[] keyBytes = Decoders.BASE64.decode("413F4428472B4BB6250655368566D5970337336763979244226452948404D6351");
        return Keys.hmacShaKeyFor(keyBytes);
    }
}
