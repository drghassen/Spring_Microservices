package org.springboot.gateway.filter;

import lombok.RequiredArgsConstructor;
import org.springboot.gateway.util.JwtUtil;
import org.springframework.cloud.gateway.filter.GatewayFilter;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.http.server.reactive.ServerHttpResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.util.List;

@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter implements GatewayFilter {
    private final JwtUtil jwtUtil;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();

        String authorizationHeader = request.getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
        if (authorizationHeader == null || !authorizationHeader.startsWith("Bearer ")) {
            return onAccessDenied(exchange);
        }

        String token = authorizationHeader.substring("Bearer ".length()).trim();
        if (token.isEmpty() || token.chars().anyMatch(Character::isWhitespace)) {
            return onAccessDenied(exchange);
        }

        try {
            jwtUtil.validateToken(token);

            List<String> roles = jwtUtil.getRolesFromToken(token);
            List<String> requiredRoles = exchange.getAttribute("requiredRoles");

            if (!isValidRoleList(roles) || !isValidRoleList(requiredRoles)) {
                return onError(exchange);
            }

            if (!userHasRequiredRoles(roles, requiredRoles)) {
                return onAccessDenied(exchange);
            }
        } catch (Exception e) {
            return onError(exchange);
        }

        return chain.filter(exchange);
    }

    private boolean isValidRoleList(List<?> roles) {
        return roles != null
                && !roles.isEmpty()
                && roles.stream().allMatch(role -> role instanceof String && !((String) role).isBlank());
    }

    private boolean userHasRequiredRoles(List<?> userRoles, List<?> requiredRoles) {
        return userRoles.stream().anyMatch(requiredRoles::contains);
    }

    private Mono<Void> onError(ServerWebExchange exchange) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(HttpStatus.FORBIDDEN);
        return response.setComplete();
    }

    private Mono<Void> onAccessDenied(ServerWebExchange exchange) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(HttpStatus.UNAUTHORIZED);
        return response.setComplete();
    }
}
