package org.springboot.gateway.blocking;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springboot.gateway.config.IpBlockingProperties;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.Clock;
import java.time.Duration;

@Service
public class AbuseWindowService {

    private static final Logger log = LoggerFactory.getLogger(AbuseWindowService.class);

    private final RedisAbuseWindowRepository repository;
    private final IpBlockingProperties properties;
    private final IpBlockingMetrics metrics;
    private final Clock clock;

    public AbuseWindowService(
            RedisAbuseWindowRepository repository,
            IpBlockingProperties properties,
            IpBlockingMetrics metrics,
            Clock clock) {
        this.repository = repository;
        this.properties = properties;
        this.metrics = metrics;
        this.clock = clock;
    }

    public Mono<AbuseDecision> recordRateLimitRejection(String safeClientKey) {
        if (properties.getMode() == IpBlockingProperties.Mode.OFF) {
            return Mono.just(AbuseDecision.none(currentWindowId()));
        }

        long nowMillis = clock.millis();
        long windowDurationMillis = properties.getWindow().getDuration().toMillis();
        long windowId = Math.floorDiv(nowMillis, windowDurationMillis);
        long nextWindowStart = Math.multiplyExact(windowId + 1, windowDurationMillis);
        Duration windowStateTtl = Duration.ofMillis(nextWindowStart - nowMillis + windowDurationMillis);
        Duration sequenceTtl = properties.getWindow().getDuration()
                .multipliedBy(properties.getWindow().getAbusiveWindowsRequired() + 1L);

        return repository.recordRateLimitRejection(
                        safeClientKey, windowId, windowStateTtl, sequenceTtl, properties)
                .map(result -> mapResult(result, safeClientKey, windowId))
                .onErrorResume(exception -> {
                    metrics.redisError();
                    log.error("event=REDIS_BLOCKING_FAILURE client_key={} mode={} operation=record_rejection",
                            safeClientKey, properties.getMode(), exception);
                    return Mono.just(new AbuseDecision(
                            AbuseDecision.Type.REDIS_FAILURE, 0, windowId));
                });
    }

    private AbuseDecision mapResult(long result, String safeClientKey, long windowId) {
        int required = properties.getWindow().getAbusiveWindowsRequired();
        if (result > RedisAbuseWindowRepository.BELOW_THRESHOLD) {
            int count = Math.toIntExact(result);
            metrics.abusiveWindow();
            log.info("event=ABUSIVE_WINDOW_DETECTED client_key={} window_id={} window_count={} mode={}",
                    safeClientKey, windowId, count, properties.getMode());
            return new AbuseDecision(AbuseDecision.Type.ABUSIVE_WINDOW, count, windowId);
        }
        if (result == RedisAbuseWindowRepository.WOULD_BLOCK) {
            metrics.abusiveWindow();
            metrics.wouldBlock();
            log.info("event=ABUSIVE_WINDOW_DETECTED client_key={} window_id={} window_count={} mode={}",
                    safeClientKey, windowId, required, properties.getMode());
            log.warn("event=WOULD_BLOCK client_key={} window_id={} window_count={} mode={}",
                    safeClientKey, windowId, required, properties.getMode());
            return new AbuseDecision(AbuseDecision.Type.WOULD_BLOCK, required, windowId);
        }
        if (result == RedisAbuseWindowRepository.BLOCK_CREATED) {
            metrics.abusiveWindow();
            metrics.blockCreated();
            log.info("event=ABUSIVE_WINDOW_DETECTED client_key={} window_id={} window_count={} mode={}",
                    safeClientKey, windowId, required, properties.getMode());
            log.warn("event=TEMP_BLOCK_CREATED client_key={} window_id={} window_count={} block_seconds={} mode={}",
                    safeClientKey, windowId, required, properties.getBlock().getDuration().toSeconds(),
                    properties.getMode());
            return new AbuseDecision(AbuseDecision.Type.BLOCK_CREATED, required, windowId);
        }
        if (result == RedisAbuseWindowRepository.BLOCK_ALREADY_ACTIVE) {
            return new AbuseDecision(AbuseDecision.Type.BLOCK_ALREADY_ACTIVE, 0, windowId);
        }
        return AbuseDecision.none(windowId);
    }

    private long currentWindowId() {
        return Math.floorDiv(clock.millis(), properties.getWindow().getDuration().toMillis());
    }
}
