package org.springboot.gateway.filter;

import org.springboot.gateway.blocking.IpBlockingExchangeAttributes;
import org.springframework.cloud.gateway.filter.GatewayFilter;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.core.Ordered;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

public class RateLimitOutcomeFilter implements GatewayFilter, Ordered {

    public static final int ORDER = 0;

    private final GatewayFilter requestRateLimiter;

    public RateLimitOutcomeFilter(GatewayFilter requestRateLimiter) {
        this.requestRateLimiter = requestRateLimiter;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        exchange.getAttributes().remove(IpBlockingExchangeAttributes.RATE_LIMIT_PASSED);
        exchange.getAttributes().remove(IpBlockingExchangeAttributes.RATE_LIMIT_REJECTED);

        return requestRateLimiter.filter(exchange, delegatedExchange -> {
                    delegatedExchange.getAttributes().put(
                            IpBlockingExchangeAttributes.RATE_LIMIT_PASSED, Boolean.TRUE);
                    return chain.filter(delegatedExchange);
                })
                .then(Mono.fromRunnable(() -> {
                    boolean passed = Boolean.TRUE.equals(exchange.getAttribute(
                            IpBlockingExchangeAttributes.RATE_LIMIT_PASSED));
                    if (!passed && exchange.getResponse().getStatusCode() == HttpStatus.TOO_MANY_REQUESTS) {
                        exchange.getAttributes().put(
                                IpBlockingExchangeAttributes.RATE_LIMIT_REJECTED, Boolean.TRUE);
                    }
                }));
    }

    @Override
    public int getOrder() {
        return ORDER;
    }

    @Override
    public String toString() {
        return "RateLimitOutcomeFilter{RequestRateLimiter}";
    }
}
