package org.springboot.gateway.blocking;

import org.springboot.gateway.config.IpBlockingProperties;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.List;

@Repository
public class RedisAbuseWindowRepository {

    static final String KEY_PREFIX = "abuse:v1:";
    static final long BELOW_THRESHOLD = 0;
    static final long WOULD_BLOCK = -2;
    static final long BLOCK_CREATED = -3;
    static final long BLOCK_ALREADY_ACTIVE = -4;

    private static final DefaultRedisScript<Long> RECORD_REJECTION_SCRIPT =
            new DefaultRedisScript<>("""
                    local mode = ARGV[6]
                    if mode == 'ENFORCE' and redis.call('PTTL', KEYS[3]) > 0 then
                        return -4
                    end

                    local window_count = redis.call('INCR', KEYS[1])
                    if window_count == 1 then
                        redis.call('PEXPIRE', KEYS[1], ARGV[1])
                    end
                    if window_count ~= tonumber(ARGV[2]) then
                        return 0
                    end

                    local window_id = tonumber(ARGV[3])
                    local previous_window = redis.call('HGET', KEYS[2], 'last_window')
                    local strikes = 1
                    if previous_window and window_id == tonumber(previous_window) + 1 then
                        strikes = tonumber(redis.call('HGET', KEYS[2], 'count') or '0') + 1
                    end

                    redis.call('HSET', KEYS[2],
                        'last_window', ARGV[3],
                        'count', strikes)
                    redis.call('PEXPIRE', KEYS[2], ARGV[4])

                    if strikes < tonumber(ARGV[5]) then
                        return strikes
                    end

                    redis.call('DEL', KEYS[2])
                    if mode == 'ENFORCE' then
                        local created = redis.call('SET', KEYS[3], '1', 'PX', ARGV[7], 'NX')
                        if created then
                            return -3
                        end
                        return -4
                    end
                    return -2
                    """, Long.class);

    private static final DefaultRedisScript<Long> BLOCK_TTL_SCRIPT =
            new DefaultRedisScript<>("return redis.call('PTTL', KEYS[1])", Long.class);

    private final ReactiveStringRedisTemplate redisTemplate;

    public RedisAbuseWindowRepository(ReactiveStringRedisTemplate redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    public Mono<Long> recordRateLimitRejection(
            String safeClientKey,
            long windowId,
            Duration windowStateTtl,
            Duration sequenceTtl,
            IpBlockingProperties properties) {
        List<String> keys = List.of(
                windowKey(safeClientKey, windowId),
                sequenceKey(safeClientKey),
                blockKey(safeClientKey));
        List<String> arguments = List.of(
                milliseconds(windowStateTtl),
                Integer.toString(properties.getWindow().getRateLimit429Threshold()),
                Long.toString(windowId),
                milliseconds(sequenceTtl),
                Integer.toString(properties.getWindow().getAbusiveWindowsRequired()),
                properties.getMode().name(),
                milliseconds(properties.getBlock().getDuration()));

        return redisTemplate.execute(RECORD_REJECTION_SCRIPT, keys, arguments).single();
    }

    public Mono<Long> remainingBlockTtlMillis(String safeClientKey) {
        return redisTemplate.execute(BLOCK_TTL_SCRIPT, List.of(blockKey(safeClientKey))).single();
    }

    static String windowKey(String safeClientKey, long windowId) {
        return KEY_PREFIX + "window:" + safeClientKey + ":" + windowId;
    }

    static String sequenceKey(String safeClientKey) {
        return KEY_PREFIX + "sequence:" + safeClientKey;
    }

    static String blockKey(String safeClientKey) {
        return KEY_PREFIX + "block:" + safeClientKey;
    }

    private String milliseconds(Duration duration) {
        return Long.toString(Math.max(1, duration.toMillis()));
    }
}
