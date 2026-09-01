package org.springboot.gateway.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.cloud.gateway.filter.GatewayFilter;
import org.springframework.cloud.gateway.filter.factory.RequestRateLimiterGatewayFilterFactory;
import org.springframework.cloud.gateway.filter.ratelimit.RateLimiter;
import org.springframework.http.HttpStatus;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class RequestRateLimiterFilterTest {

    private GatewayFilter filter;

    @BeforeEach
    void setUp() {
        Map<String, Integer> requestsByKey = new HashMap<>();
        @SuppressWarnings("unchecked")
        RateLimiter<Object> rateLimiter = mock(RateLimiter.class);
        when(rateLimiter.isAllowed(anyString(), anyString())).thenAnswer(invocation -> {
            String key = invocation.getArgument(1);
            boolean allowed = requestsByKey.merge(key, 1, Integer::sum) <= 1;
            return Mono.just(new RateLimiter.Response(allowed, Map.of()));
        });

        ClientIpKeyResolver keyResolver = new ClientIpKeyResolver();
        RequestRateLimiterGatewayFilterFactory.Config config =
                new RequestRateLimiterGatewayFilterFactory.Config()
                        .setRateLimiter(rateLimiter)
                        .setKeyResolver(keyResolver)
                        .setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
        config.setRouteId("auth-rate-limit-test");
        filter = new RequestRateLimiterGatewayFilterFactory(rateLimiter, keyResolver).apply(config);
    }

    @Test
    void shouldAllowUnderLimitRejectSameIpAndKeepDifferentIpsIndependent() {
        FilterResult firstRequest = execute("198.51.100.10", "untrusted-value");
        FilterResult sameIpRequest = execute("198.51.100.10", "another-untrusted-value");
        FilterResult differentIpRequest = execute("198.51.100.11", "untrusted-value");

        assertThat(firstRequest.downstreamCalled()).isTrue();
        assertThat(firstRequest.exchange().getResponse().getStatusCode()).isNull();

        assertThat(sameIpRequest.downstreamCalled()).isFalse();
        assertThat(sameIpRequest.exchange().getResponse().getStatusCode())
                .isEqualTo(HttpStatus.TOO_MANY_REQUESTS);

        assertThat(differentIpRequest.downstreamCalled()).isTrue();
        assertThat(differentIpRequest.exchange().getResponse().getStatusCode()).isNull();
    }

    private FilterResult execute(String clientIp, String forwardedFor) {
        MockServerHttpRequest request = MockServerHttpRequest.get("/api/v1/auth/login")
                .header(ClientIpKeyResolver.CLIENT_IP_HEADER, clientIp)
                .header("X-Forwarded-For", forwardedFor)
                .remoteAddress(new java.net.InetSocketAddress("10.0.0.5", 12345))
                .build();
        MockServerWebExchange exchange = MockServerWebExchange.from(request);
        AtomicBoolean downstreamCalled = new AtomicBoolean();

        filter.filter(exchange, ignored -> {
            downstreamCalled.set(true);
            return Mono.empty();
        }).block(Duration.ofSeconds(5));

        return new FilterResult(exchange, downstreamCalled.get());
    }

    private record FilterResult(MockServerWebExchange exchange, boolean downstreamCalled) {
    }
}
