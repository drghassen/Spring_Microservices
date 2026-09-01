package org.springboot.gateway.filter;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springboot.gateway.blocking.AbuseDecision;
import org.springboot.gateway.blocking.AbuseWindowService;
import org.springboot.gateway.blocking.IpBlockingExchangeAttributes;
import org.springboot.gateway.config.IpBlockingProperties;
import org.springframework.cloud.gateway.filter.GatewayFilter;
import org.springframework.http.HttpStatus;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import reactor.core.publisher.Mono;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RateLimitObservationTest {

    private AbuseWindowService abuseWindowService;
    private IpBlockingProperties properties;
    private RateLimitAbuseObserver observer;

    @BeforeEach
    void setUp() {
        abuseWindowService = mock(AbuseWindowService.class);
        properties = new IpBlockingProperties();
        properties.setMode(IpBlockingProperties.Mode.SHADOW);
        observer = new RateLimitAbuseObserver(abuseWindowService, properties);
    }

    @Test
    void nativeRateLimiterRejectionIsMarkedAndObserved() {
        MockServerWebExchange exchange = exchange();
        exchange.getAttributes().put(IpBlockingExchangeAttributes.SAFE_CLIENT_KEY, "safe-key");
        when(abuseWindowService.recordRateLimitRejection("safe-key"))
                .thenReturn(Mono.just(AbuseDecision.none(1)));
        GatewayFilter nativeRejection = (current, ignored) -> {
            current.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
            return current.getResponse().setComplete();
        };
        RateLimitOutcomeFilter outcomeFilter = new RateLimitOutcomeFilter(nativeRejection);

        observer.filter(exchange, current -> outcomeFilter.filter(current, ignored -> Mono.empty())).block();

        assertThat((Object) exchange.getAttribute(IpBlockingExchangeAttributes.RATE_LIMIT_REJECTED))
                .isEqualTo(Boolean.TRUE);
        verify(abuseWindowService).recordRateLimitRejection("safe-key");
    }

    @Test
    void application429AfterRateLimiterPassedIsNotObserved() {
        MockServerWebExchange exchange = exchange();
        exchange.getAttributes().put(IpBlockingExchangeAttributes.SAFE_CLIENT_KEY, "safe-key");
        GatewayFilter allowingRateLimiter = (current, chain) -> chain.filter(current);
        RateLimitOutcomeFilter outcomeFilter = new RateLimitOutcomeFilter(allowingRateLimiter);

        observer.filter(exchange, current -> outcomeFilter.filter(current, backendExchange -> {
            backendExchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
            return backendExchange.getResponse().setComplete();
        })).block();

        assertThat((Object) exchange.getAttribute(IpBlockingExchangeAttributes.RATE_LIMIT_PASSED))
                .isEqualTo(Boolean.TRUE);
        assertThat((Object) exchange.getAttribute(IpBlockingExchangeAttributes.RATE_LIMIT_REJECTED))
                .isNull();
        verify(abuseWindowService, never()).recordRateLimitRejection("safe-key");
    }

    @Test
    void temporaryBlock429AndOffModeAreNeverObserved() {
        MockServerWebExchange blockedExchange = exchange();
        blockedExchange.getAttributes().put(IpBlockingExchangeAttributes.SAFE_CLIENT_KEY, "safe-key");
        blockedExchange.getAttributes().put(IpBlockingExchangeAttributes.RATE_LIMIT_REJECTED, Boolean.TRUE);
        blockedExchange.getAttributes().put(IpBlockingExchangeAttributes.TEMP_BLOCK_REJECTED, Boolean.TRUE);

        observer.filter(blockedExchange, current -> {
            current.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
            return current.getResponse().setComplete();
        }).block();

        properties.setMode(IpBlockingProperties.Mode.OFF);
        MockServerWebExchange offExchange = exchange();
        offExchange.getAttributes().put(IpBlockingExchangeAttributes.SAFE_CLIENT_KEY, "safe-key");
        offExchange.getAttributes().put(IpBlockingExchangeAttributes.RATE_LIMIT_REJECTED, Boolean.TRUE);
        observer.filter(offExchange, current -> {
            current.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
            return current.getResponse().setComplete();
        }).block();

        verify(abuseWindowService, never()).recordRateLimitRejection("safe-key");
    }

    private MockServerWebExchange exchange() {
        return MockServerWebExchange.from(MockServerHttpRequest.get("/api/v1/auth/login"));
    }
}
