package org.springboot.gateway;

import org.junit.jupiter.api.Test;
import org.springboot.gateway.filter.JwtAuthenticationFilter;
import org.springboot.gateway.util.JwtUtil;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.http.server.reactive.ServerHttpResponse;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.*;

@SpringBootTest
public class GatewayAuthFilter {
   /* private final JwtUtil jwtUtil = mock(JwtUtil.class); // Mocked JwtUtil
    private final List<String> OPEN_ENDPOINTS = List.of("/public", "/health");
    private final JwtAuthenticationFilter filter = new JwtAuthenticationFilter(jwtUtil);

    @Test
    public void testFilter_withOpenEndpoint() {
        ServerWebExchange exchange = mock(ServerWebExchange.class);
        ServerHttpRequest request = mock(ServerHttpRequest.class);
        GatewayFilterChain chain = mock(GatewayFilterChain.class);
        when(exchange.getRequest()).thenReturn(request);
        when(request.getURI().getPath()).thenReturn("/public");
        when(chain.filter(exchange)).thenReturn(Mono.empty());
        Mono<Void> result = filter.filter(exchange, chain);
        verify(chain, times(1)).filter(exchange); // Verify chain is called
        assertEquals(Mono.empty(), result); // No interruption for open endpoints
    }

    @Test
    public void testFilter_missingAuthorizationHeader() {
        ServerWebExchange exchange = mock(ServerWebExchange.class);
        ServerHttpRequest request = mock(ServerHttpRequest.class);
        ServerHttpResponse response = mock(ServerHttpResponse.class);

        when(exchange.getRequest()).thenReturn(request);
        when(exchange.getResponse()).thenReturn(response);
        when(request.getURI().getPath()).thenReturn("/secured");
        when(request.getHeaders()).thenReturn(new HttpHeaders());
        when(response.setComplete()).thenReturn(Mono.empty());

        Mono<Void> result = filter.filter(exchange, null);

        verify(response, times(1)).setStatusCode(HttpStatus.UNAUTHORIZED);
        assertEquals(Mono.empty(), result); // Request is blocked
    }

    @Test
    public void testFilter_invalidToken() {
        ServerWebExchange exchange = mock(ServerWebExchange.class);
        ServerHttpRequest request = mock(ServerHttpRequest.class);
        ServerHttpResponse response = mock(ServerHttpResponse.class);
        GatewayFilterChain chain = mock(GatewayFilterChain.class);

        HttpHeaders headers = new HttpHeaders();
        headers.add("Authorization", "Bearer invalidToken");

        when(exchange.getRequest()).thenReturn(request);
        when(exchange.getResponse()).thenReturn(response);
        when(request.getURI().getPath()).thenReturn("/secured");
        when(request.getHeaders()).thenReturn(headers);
        when(response.setComplete()).thenReturn(Mono.empty());

        doThrow(new RuntimeException("Invalid token")).when(jwtUtil).validateToken("invalidToken");

        Mono<Void> result = filter.filter(exchange, chain);

        verify(response, times(1)).setStatusCode(HttpStatus.FORBIDDEN);
        assertEquals(Mono.empty(), result); // Request is blocked
    }

    @Test
    public void testFilter_validToken_insufficientRoles() {
        ServerWebExchange exchange = mock(ServerWebExchange.class);
        ServerHttpRequest request = mock(ServerHttpRequest.class);
        ServerHttpResponse response = mock(ServerHttpResponse.class);
        GatewayFilterChain chain = mock(GatewayFilterChain.class);

        HttpHeaders headers = new HttpHeaders();
        headers.add("Authorization", "Bearer validToken");

        when(exchange.getRequest()).thenReturn(request);
        when(exchange.getResponse()).thenReturn(response);
        when(exchange.getAttribute("requiredRoles")).thenReturn(List.of("ROLE_ADMIN"));
        when(request.getURI().getPath()).thenReturn("/secured");
        when(request.getHeaders()).thenReturn(headers);
        when(response.setComplete()).thenReturn(Mono.empty());

        when(jwtUtil.getRolesFromToken("validToken")).thenReturn(List.of("ROLE_USER"));
        doNothing().when(jwtUtil).validateToken("validToken");

        Mono<Void> result = filter.filter(exchange, chain);

        verify(response, times(1)).setStatusCode(HttpStatus.UNAUTHORIZED);
        assertEquals(Mono.empty(), result); // Request is blocked
    }

    @Test
    public void testFilter_validToken_sufficientRoles() {
        ServerWebExchange exchange = mock(ServerWebExchange.class);
        ServerHttpRequest request = mock(ServerHttpRequest.class);
        GatewayFilterChain chain = mock(GatewayFilterChain.class);

        HttpHeaders headers = new HttpHeaders();
        headers.add("Authorization", "Bearer validToken");

        when(exchange.getRequest()).thenReturn(request);
        when(exchange.getAttribute("requiredRoles")).thenReturn(List.of("ROLE_USER"));
        when(request.getURI().getPath()).thenReturn("/secured");
        when(request.getHeaders()).thenReturn(headers);
        when(chain.filter(exchange)).thenReturn(Mono.empty());

        when(jwtUtil.getRolesFromToken("validToken")).thenReturn(List.of("ROLE_USER"));
        doNothing().when(jwtUtil).validateToken("validToken");

        Mono<Void> result = filter.filter(exchange, chain);

        verify(chain, times(1)).filter(exchange); // Chain is called
        assertEquals(Mono.empty(), result); // Request proceeds
    }*/
}
