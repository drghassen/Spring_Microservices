package org.springboot.gateway.config;

import org.junit.jupiter.api.Test;
import org.springframework.cloud.gateway.filter.ratelimit.RateLimiter;
import org.springframework.cloud.gateway.filter.ratelimit.RedisRateLimiter;
import org.springframework.cloud.gateway.support.ConfigurationService;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import reactor.core.publisher.Flux;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class RedisRateLimiterFailureModeTest {

    @Test
    void shouldDocumentNativeFailOpenBehaviorWhenRedisIsUnavailable() {
        ReactiveStringRedisTemplate redisTemplate = mock(ReactiveStringRedisTemplate.class);
        @SuppressWarnings("unchecked")
        RedisScript<List<Long>> script = mock(RedisScript.class);
        ConfigurationService configurationService = mock(ConfigurationService.class);

        when(redisTemplate.execute(eq(script), anyList(), anyList()))
                .thenReturn(Flux.error(new DataAccessResourceFailureException("Redis unavailable")));

        RedisRateLimiter rateLimiter = new RedisRateLimiter(redisTemplate, script, configurationService);
        rateLimiter.getConfig().put("auth", new RedisRateLimiter.Config()
                .setReplenishRate(5)
                .setBurstCapacity(10));

        RateLimiter.Response response = rateLimiter.isAllowed("auth", "ip:198.51.100.12").block();

        assertThat(response).isNotNull();
        assertThat(response.isAllowed()).isTrue();
        assertThat(response.getHeaders()).containsEntry(RedisRateLimiter.REMAINING_HEADER, "-1");
    }
}
