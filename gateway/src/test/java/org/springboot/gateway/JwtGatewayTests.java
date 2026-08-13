package org.springboot.gateway;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springboot.gateway.util.JwtUtil;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;

import java.security.Key;
import java.util.Date;
import java.util.List;

import static java.util.List.of;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
class JwtGatewayTests {

    @Autowired
    private JwtUtil jwtUtil;
    @Value("${jwt.secret}")
    private String secretKey;
    private String validToken;
    private String invalidToken;

    @BeforeEach
    void setUp() {
        // Generate a valid token for testing
        validToken = Jwts.builder()
                .setSubject("test-user")
                .claim("roles", of("USER", "ADMIN"))
                .setIssuedAt(new Date())
                .setExpiration(new Date(System.currentTimeMillis() + 1000 * 60 * 60)) // 1 hour validity
                .signWith(getSignKey(), SignatureAlgorithm.HS256)
                .compact();

        // Create an invalid token signed with a different key — guarantees SignatureException
        String differentKey = "5468576D5A7134743777217A25432A462D4A614E645267556B58703272357538";
        byte[] differentKeyBytes = Decoders.BASE64.decode(differentKey);
        Key wrongKey = Keys.hmacShaKeyFor(differentKeyBytes);
        invalidToken = Jwts.builder()
                .setSubject("test-user")
                .claim("roles", of("USER", "ADMIN"))
                .setIssuedAt(new Date())
                .setExpiration(new Date(System.currentTimeMillis() + 1000 * 60 * 60))
                .signWith(wrongKey, SignatureAlgorithm.HS256)
                .compact();
    }

    private Key getSignKey() {
        byte[] keyBytes = Decoders.BASE64.decode(secretKey);
        return Keys.hmacShaKeyFor(keyBytes);
    }

    @Test
    void shouldValidateTokenSuccessfully() {
        // Act & Assert
        jwtUtil.validateToken(validToken); // No exceptions means the test passes
    }

    @Test
    void shouldThrowExceptionForInvalidToken() {
        // Act & Assert
        assertThatThrownBy(() -> jwtUtil.validateToken(invalidToken))
                .isInstanceOf(io.jsonwebtoken.JwtException.class);
    }

    @Test
    void shouldExtractRolesFromValidToken() {
        // Act
        List<String> roles = jwtUtil.getRolesFromToken(validToken);

        // Assert
        assertThat(roles).isNotNull().containsExactlyInAnyOrder("USER", "ADMIN");
    }


}
