package org.springboot.gateway.blocking;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springboot.gateway.config.IpBlockingProperties;
import org.springframework.dao.DataAccessResourceFailureException;
import reactor.core.publisher.Mono;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AbuseWindowServiceFailureTest {

    @Test
    void recordingFailureIsObservableAndFailOpen() {
        RedisAbuseWindowRepository repository = mock(RedisAbuseWindowRepository.class);
        IpBlockingProperties properties = new IpBlockingProperties();
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        when(repository.recordRateLimitRejection(
                anyString(), anyLong(), any(), any(), any()))
                .thenReturn(Mono.error(new DataAccessResourceFailureException("Redis unavailable")));
        AbuseWindowService service = new AbuseWindowService(
                repository, properties, new IpBlockingMetrics(registry, properties),
                new MutableClock(Instant.ofEpochSecond(1_000)));

        AbuseDecision decision = service.recordRateLimitRejection("safe-key").block();

        assertThat(decision.type()).isEqualTo(AbuseDecision.Type.REDIS_FAILURE);
        assertThat(registry.counter("ip_blocking_redis_errors_total",
                "mode", "SHADOW", "route_category", "auth").count()).isEqualTo(1);
    }

    @Test
    void offModeMakesNoRedisDecision() {
        RedisAbuseWindowRepository repository = mock(RedisAbuseWindowRepository.class);
        IpBlockingProperties properties = new IpBlockingProperties();
        properties.setMode(IpBlockingProperties.Mode.OFF);
        AbuseWindowService service = new AbuseWindowService(
                repository, properties,
                new IpBlockingMetrics(new SimpleMeterRegistry(), properties),
                new MutableClock(Instant.ofEpochSecond(1_000)));

        AbuseDecision decision = service.recordRateLimitRejection("safe-key").block();

        assertThat(decision.type()).isEqualTo(AbuseDecision.Type.NONE);
        verify(repository, never()).recordRateLimitRejection(
                anyString(), anyLong(), any(), any(), any());
    }
}
