package org.springboot.gateway.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpHeaders;
import org.springframework.web.server.WebFilter;

@Configuration
public class SecurityHeadersConfig {

    @Bean
    public WebFilter securityHeadersWebFilter() {
        return (exchange, chain) -> {
            HttpHeaders headers = exchange.getResponse().getHeaders();
            headers.set("X-Content-Type-Options", "nosniff");
            headers.set("Cross-Origin-Resource-Policy", "same-site");
            return chain.filter(exchange);
        };
    }
}
