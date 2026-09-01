package org.springboot.gateway.filter;

import org.springboot.gateway.blocking.AbuseWindowService;
import org.springboot.gateway.blocking.IpBlockingExchangeAttributes;
import org.springboot.gateway.config.IpBlockingProperties;
import org.springframework.cloud.gateway.filter.GatewayFilter;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.core.Ordered;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

@Component
public class RateLimitAbuseObserver implements GatewayFilter, Ordered {

    public static final int ORDER = -20;

    private final AbuseWindowService abuseWindowService;
    private final IpBlockingProperties properties;

    public RateLimitAbuseObserver(
            AbuseWindowService abuseWindowService,
            IpBlockingProperties properties) {
        this.abuseWindowService = abuseWindowService;
        this.properties = properties;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        return chain.filter(exchange).then(Mono.defer(() -> observe(exchange)));
    }

    private Mono<Void> observe(ServerWebExchange exchange) {
        if (properties.getMode() == IpBlockingProperties.Mode.OFF
                || exchange.getResponse().getStatusCode() != HttpStatus.TOO_MANY_REQUESTS
                || !Boolean.TRUE.equals(exchange.getAttribute(
                        IpBlockingExchangeAttributes.RATE_LIMIT_REJECTED))
                || Boolean.TRUE.equals(exchange.getAttribute(
                        IpBlockingExchangeAttributes.TEMP_BLOCK_REJECTED))) {
            return Mono.empty();
        }

        String safeClientKey = exchange.getAttribute(IpBlockingExchangeAttributes.SAFE_CLIENT_KEY);
        if (safeClientKey == null) {
            return Mono.empty();
        }
        return abuseWindowService.recordRateLimitRejection(safeClientKey).then();
    }

    @Override
    public int getOrder() {
        return ORDER;
    }
}
