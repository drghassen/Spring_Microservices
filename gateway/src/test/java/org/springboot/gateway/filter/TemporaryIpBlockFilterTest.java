package org.springboot.gateway.filter;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springboot.gateway.blocking.ClientKeyHasher;
import org.springboot.gateway.blocking.IpBlockingMetrics;
import org.springboot.gateway.blocking.RedisAbuseWindowRepository;
import org.springboot.gateway.config.ClientIpKeyResolver;
import org.springboot.gateway.config.IpBlockingProperties;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class TemporaryIpBlockFilterTest {

    private RedisAbuseWindowRepository repository;
    private IpBlockingProperties properties;
    private TemporaryIpBlockFilter filter;

    @BeforeEach
    void setUp() {
        repository = mock(RedisAbuseWindowRepository.class);
        properties = new IpBlockingProperties();
        properties.setMode(IpBlockingProperties.Mode.ENFORCE);
        filter = new TemporaryIpBlockFilter(new ClientIpKeyResolver(), repository, properties,
                new IpBlockingMetrics(new SimpleMeterRegistry(), properties));
    }

    @Test
    void activeBlockReturns429RetryAfterJsonAndDoesNotCallBackend() {
        String safeKey = ClientKeyHasher.hash("ip:198.51.100.60");
        when(repository.remainingBlockTtlMillis(safeKey)).thenReturn(Mono.just(47_001L));
        AtomicBoolean backendCalled = new AtomicBoolean();
        MockServerWebExchange exchange = exchange("198.51.100.60");

        filter.filter(exchange, ignored -> {
            backendCalled.set(true);
            return Mono.empty();
        }).block(Duration.ofSeconds(5));

        assertThat(backendCalled).isFalse();
        assertThat(exchange.getResponse().getStatusCode().value()).isEqualTo(429);
        assertThat(exchange.getResponse().getHeaders().getFirst("Retry-After")).isEqualTo("48");
        assertThat(exchange.getResponse().getBodyAsString().block())
                .contains("TEMPORARILY_BLOCKED")
                .doesNotContain("198.51.100.60")
                .doesNotContain("abuse:v1");
    }

    @Test
    void redisFailureIsFailOpenAndCallsBackendOnce() {
        String safeKey = ClientKeyHasher.hash("ip:198.51.100.61");
        when(repository.remainingBlockTtlMillis(safeKey)).thenReturn(Mono.error(
                new DataAccessResourceFailureException("Redis unavailable")));
        AtomicBoolean backendCalled = new AtomicBoolean();
        MockServerWebExchange exchange = exchange("198.51.100.61");

        filter.filter(exchange, ignored -> {
            backendCalled.set(true);
            return Mono.empty();
        }).block(Duration.ofSeconds(5));

        assertThat(backendCalled).isTrue();
        assertThat(exchange.getResponse().getStatusCode()).isNull();
    }

    @Test
    void shadowNeverLooksUpOrEnforcesBlock() {
        properties.setMode(IpBlockingProperties.Mode.SHADOW);
        AtomicBoolean backendCalled = new AtomicBoolean();
        MockServerWebExchange exchange = exchange("198.51.100.62");

        filter.filter(exchange, ignored -> {
            backendCalled.set(true);
            return Mono.empty();
        }).block(Duration.ofSeconds(5));

        assertThat(backendCalled).isTrue();
        verify(repository, never()).remainingBlockTtlMillis(org.mockito.ArgumentMatchers.anyString());
    }

    private MockServerWebExchange exchange(String clientIp) {
        return MockServerWebExchange.from(MockServerHttpRequest.get("/api/v1/auth/login")
                .header(ClientIpKeyResolver.CLIENT_IP_HEADER, clientIp));
    }
}
