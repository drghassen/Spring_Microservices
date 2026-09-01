package org.springboot.gateway.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springboot.gateway.filter.RateLimitOutcomeFilter;
import org.springframework.cloud.gateway.filter.factory.RequestRateLimiterGatewayFilterFactory;
import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.cloud.gateway.filter.ratelimit.RedisRateLimiter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;

@Configuration
public class RateLimitConfig {

    @Bean
    public RedisRateLimiter authRedisRateLimiter(
            @Value("${rate-limit.auth.replenish-rate}") int replenishRate,
            @Value("${rate-limit.auth.burst-capacity}") int burstCapacity) {
        return new RedisRateLimiter(replenishRate, burstCapacity);
    }

    @Bean
    public RateLimitOutcomeFilter authRateLimitOutcomeFilter(
            RequestRateLimiterGatewayFilterFactory factory,
            @Qualifier("authRedisRateLimiter") RedisRateLimiter rateLimiter,
            @Qualifier("clientIpKeyResolver") KeyResolver keyResolver) {
        RequestRateLimiterGatewayFilterFactory.Config config =
                new RequestRateLimiterGatewayFilterFactory.Config()
                        .setRateLimiter(rateLimiter)
                        .setKeyResolver(keyResolver)
                        .setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
        config.setRouteId("auth");
        return new RateLimitOutcomeFilter(factory.apply(config));
    }
}
