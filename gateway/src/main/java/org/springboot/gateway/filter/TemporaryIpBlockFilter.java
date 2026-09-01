package org.springboot.gateway.filter;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springboot.gateway.blocking.ClientKeyHasher;
import org.springboot.gateway.blocking.IpBlockingExchangeAttributes;
import org.springboot.gateway.blocking.IpBlockingMetrics;
import org.springboot.gateway.blocking.RedisAbuseWindowRepository;
import org.springboot.gateway.config.IpBlockingProperties;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.cloud.gateway.filter.GatewayFilter;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.core.Ordered;
import org.springframework.core.io.buffer.DataBuffer;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;

@Component
public class TemporaryIpBlockFilter implements GatewayFilter, Ordered {

    public static final int ORDER = -30;
    private static final Logger log = LoggerFactory.getLogger(TemporaryIpBlockFilter.class);
    private static final byte[] BLOCK_RESPONSE = """
            {"status":429,"error":"Too Many Requests","reason":"TEMPORARILY_BLOCKED"}
            """.strip().getBytes(StandardCharsets.UTF_8);

    private final KeyResolver clientIpKeyResolver;
    private final RedisAbuseWindowRepository repository;
    private final IpBlockingProperties properties;
    private final IpBlockingMetrics metrics;

    public TemporaryIpBlockFilter(
            @Qualifier("clientIpKeyResolver") KeyResolver clientIpKeyResolver,
            RedisAbuseWindowRepository repository,
            IpBlockingProperties properties,
            IpBlockingMetrics metrics) {
        this.clientIpKeyResolver = clientIpKeyResolver;
        this.repository = repository;
        this.properties = properties;
        this.metrics = metrics;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        return clientIpKeyResolver.resolve(exchange).flatMap(clientKey -> {
            String safeClientKey = ClientKeyHasher.hash(clientKey);
            exchange.getAttributes().put(IpBlockingExchangeAttributes.SAFE_CLIENT_KEY, safeClientKey);

            if (properties.getMode() != IpBlockingProperties.Mode.ENFORCE) {
                return chain.filter(exchange);
            }

            return repository.remainingBlockTtlMillis(safeClientKey)
                    .onErrorResume(exception -> failOpenTtl(safeClientKey, exception))
                    .flatMap(ttlMillis -> handleTtl(exchange, chain, safeClientKey, ttlMillis));
        });
    }

    private Mono<Void> handleTtl(
            ServerWebExchange exchange,
            GatewayFilterChain chain,
            String safeClientKey,
            long ttlMillis) {
        if (ttlMillis > 0) {
            long retryAfterSeconds = Math.max(1, (ttlMillis + 999) / 1000);
            exchange.getAttributes().put(IpBlockingExchangeAttributes.TEMP_BLOCK_REJECTED, Boolean.TRUE);
            exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
            exchange.getResponse().getHeaders().set(HttpHeaders.RETRY_AFTER,
                    Long.toString(retryAfterSeconds));
            exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
            metrics.requestRejected();
            log.warn("event=TEMP_BLOCK_REJECTED client_key={} remaining_ttl_seconds={} mode={}",
                    safeClientKey, retryAfterSeconds, properties.getMode());
            DataBuffer body = exchange.getResponse().bufferFactory().wrap(BLOCK_RESPONSE);
            return exchange.getResponse().writeWith(Mono.just(body));
        }

        if (ttlMillis == -1) {
            metrics.redisError();
            log.error("event=REDIS_BLOCKING_FAILURE client_key={} mode={} operation=block_ttl reason=missing_ttl",
                    safeClientKey, properties.getMode());
        }
        return chain.filter(exchange);
    }

    private Mono<Long> failOpenTtl(
            String safeClientKey,
            Throwable exception) {
        metrics.redisError();
        log.error("event=REDIS_BLOCKING_FAILURE client_key={} mode={} operation=block_lookup",
                safeClientKey, properties.getMode(), exception);
        return Mono.just(-2L);
    }

    @Override
    public int getOrder() {
        return ORDER;
    }
}
