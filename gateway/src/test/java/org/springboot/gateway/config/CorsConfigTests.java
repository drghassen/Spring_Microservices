package org.springboot.gateway.config;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class CorsConfigTests {

    @Test
    void corsConfigurationShouldUseExplicitOriginsMethodsAndHeaders() {
        var source = new CorsConfig(List.of("http://localhost:4200"))
                .corsConfigurationSource();
        var exchange = MockServerWebExchange.from(
                MockServerHttpRequest.options("/api/v1/games")
                        .header(HttpHeaders.ORIGIN, "http://localhost:4200")
        );

        var configuration = source.getCorsConfiguration(exchange);

        assertThat(configuration).isNotNull();
        assertThat(configuration.getAllowedOrigins()).containsExactly("http://localhost:4200");
        assertThat(configuration.getAllowedOrigins()).doesNotContain("*");
        assertThat(configuration.getAllowedMethods()).containsExactlyInAnyOrder(
                "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"
        );
        assertThat(configuration.getAllowedMethods()).doesNotContain("*");
        assertThat(configuration.getAllowedHeaders()).containsExactlyInAnyOrder(
                HttpHeaders.AUTHORIZATION,
                HttpHeaders.CONTENT_TYPE,
                HttpHeaders.ACCEPT,
                HttpHeaders.ORIGIN,
                "X-Requested-With"
        );
        assertThat(configuration.getAllowedHeaders()).doesNotContain("*");
        assertThat(configuration.getAllowCredentials()).isFalse();
    }
}
