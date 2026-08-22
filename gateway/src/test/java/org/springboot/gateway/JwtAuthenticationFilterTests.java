package org.springboot.gateway;

import io.jsonwebtoken.JwtException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springboot.gateway.filter.JwtAuthenticationFilter;
import org.springboot.gateway.util.JwtUtil;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.http.server.reactive.ServerHttpResponse;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.util.List;

import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.mock;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class JwtAuthenticationFilterTests {

    @Mock
    private JwtUtil jwtUtil;

    @Mock
    private GatewayFilterChain chain;

    private JwtAuthenticationFilter filter;

    @BeforeEach
    void setUp() {
        filter = new JwtAuthenticationFilter(jwtUtil);
    }

    @Test
    void shouldRejectProtectedRouteWithoutAuthorizationHeader() {
        ServerHttpResponse response = mockResponse();
        ServerWebExchange exchange = exchange(new HttpHeaders(), response);

        filter.filter(exchange, chain);

        verify(response).setStatusCode(HttpStatus.UNAUTHORIZED);
        verify(chain, never()).filter(exchange);
    }

    @Test
    void shouldRejectAuthorizationHeaderWithoutBearerScheme() {
        HttpHeaders headers = headers("Basic credentials");
        ServerHttpResponse response = mockResponse();
        ServerWebExchange exchange = exchange(headers, response);

        filter.filter(exchange, chain);

        verify(response).setStatusCode(HttpStatus.UNAUTHORIZED);
        verify(chain, never()).filter(exchange);
    }

    @Test
    void shouldRejectEmptyBearerToken() {
        HttpHeaders headers = headers("Bearer ");
        ServerHttpResponse response = mockResponse();
        ServerWebExchange exchange = exchange(headers, response);

        filter.filter(exchange, chain);

        verify(response).setStatusCode(HttpStatus.UNAUTHORIZED);
        verify(chain, never()).filter(exchange);
    }

    @Test
    void shouldRejectInvalidJwt() {
        HttpHeaders headers = headers("Bearer invalid-token");
        ServerHttpResponse response = mockResponse();
        ServerWebExchange exchange = exchange(headers, response);
        doThrow(new JwtException("Invalid token")).when(jwtUtil).validateToken("invalid-token");

        filter.filter(exchange, chain);

        verify(response).setStatusCode(HttpStatus.FORBIDDEN);
        verify(chain, never()).filter(exchange);
    }

    @Test
    void shouldRejectUserWithoutRequiredRole() {
        HttpHeaders headers = headers("Bearer valid-token");
        ServerHttpResponse response = mockResponse();
        ServerWebExchange exchange = exchange(headers, List.of("ADMIN"), response);
        when(jwtUtil.getRolesFromToken("valid-token")).thenReturn(List.of("USER"));

        filter.filter(exchange, chain);

        verify(response).setStatusCode(HttpStatus.UNAUTHORIZED);
        verify(chain, never()).filter(exchange);
    }

    @Test
    void shouldContinueForUserWithRequiredRole() {
        HttpHeaders headers = headers("Bearer valid-token");
        ServerWebExchange exchange = exchange(headers, List.of("USER"), null);
        when(jwtUtil.getRolesFromToken("valid-token")).thenReturn(List.of("USER"));
        when(chain.filter(exchange)).thenReturn(Mono.empty());

        filter.filter(exchange, chain);

        verify(chain).filter(exchange);
    }

    @Test
    void shouldRejectTokenWithoutValidRolesClaim() {
        HttpHeaders headers = headers("Bearer valid-token");
        ServerHttpResponse response = mockResponse();
        ServerWebExchange exchange = exchange(headers, List.of("USER"), response);
        when(jwtUtil.getRolesFromToken("valid-token")).thenReturn(List.of());

        filter.filter(exchange, chain);

        verify(response).setStatusCode(HttpStatus.FORBIDDEN);
        verify(chain, never()).filter(exchange);
    }

    @Test
    void shouldRejectMissingRequiredRoles() {
        HttpHeaders headers = headers("Bearer valid-token");
        ServerHttpResponse response = mockResponse();
        ServerWebExchange exchange = exchange(headers, List.of(), response);
        when(jwtUtil.getRolesFromToken("valid-token")).thenReturn(List.of("USER"));

        filter.filter(exchange, chain);

        verify(response).setStatusCode(HttpStatus.FORBIDDEN);
        verify(chain, never()).filter(exchange);
    }

    private ServerWebExchange exchange(HttpHeaders headers, ServerHttpResponse response) {
        ServerWebExchange exchange = mock(ServerWebExchange.class);
        ServerHttpRequest request = mock(ServerHttpRequest.class);
        when(exchange.getRequest()).thenReturn(request);
        when(request.getHeaders()).thenReturn(headers);
        if (response != null) {
            when(exchange.getResponse()).thenReturn(response);
        }
        return exchange;
    }

    private ServerWebExchange exchange(
            HttpHeaders headers,
            List<String> requiredRoles,
            ServerHttpResponse response
    ) {
        ServerWebExchange exchange = exchange(headers, response);
        when(exchange.getAttribute("requiredRoles")).thenReturn(requiredRoles);
        return exchange;
    }

    private HttpHeaders headers(String authorization) {
        HttpHeaders headers = new HttpHeaders();
        headers.set(HttpHeaders.AUTHORIZATION, authorization);
        return headers;
    }

    private ServerHttpResponse mockResponse() {
        ServerHttpResponse response = mock(ServerHttpResponse.class);
        when(response.setComplete()).thenReturn(Mono.empty());
        return response;
    }
}
