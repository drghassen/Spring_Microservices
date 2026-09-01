package org.springboot.gateway.blocking;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springboot.gateway.config.IpBlockingProperties;
import org.springboot.gateway.config.ClientIpKeyResolver;
import org.springboot.gateway.filter.RateLimitAbuseObserver;
import org.springboot.gateway.filter.RateLimitOutcomeFilter;
import org.springboot.gateway.filter.TemporaryIpBlockFilter;
import org.springframework.cloud.gateway.filter.factory.RequestRateLimiterGatewayFilterFactory;
import org.springframework.cloud.gateway.filter.ratelimit.RedisRateLimiter;
import org.springframework.cloud.gateway.support.ConfigurationService;
import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.scripting.support.ResourceScriptSource;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import redis.embedded.RedisServer;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class RedisIpBlockingIntegrationTest {

    private static RedisServer redisServer;
    private static LettuceConnectionFactory connectionFactory;
    private static ReactiveStringRedisTemplate redis;

    private IpBlockingProperties properties;
    private MutableClock clock;
    private AbuseWindowService gatewayA;
    private AbuseWindowService gatewayB;

    @BeforeAll
    static void connect() throws IOException {
        int redisPort = availablePort();
        redisServer = RedisServer.newRedisServer()
                .bind("127.0.0.1")
                .port(redisPort)
                .setting("save \"\"")
                .setting("appendonly no")
                .build();
        redisServer.start();
        connectionFactory = new LettuceConnectionFactory("127.0.0.1", redisPort);
        connectionFactory.afterPropertiesSet();
        connectionFactory.start();
        redis = new ReactiveStringRedisTemplate(connectionFactory);
    }

    @AfterAll
    static void disconnect() throws IOException {
        if (connectionFactory != null) {
            connectionFactory.destroy();
        }
        if (redisServer != null) {
            redisServer.stop();
        }
    }

    @BeforeEach
    void setUp() {
        redis.getConnectionFactory().getReactiveConnection().serverCommands().flushAll().block();
        properties = properties(IpBlockingProperties.Mode.SHADOW, Duration.ofSeconds(60));
        clock = new MutableClock(Instant.ofEpochSecond(1_000));
        RedisAbuseWindowRepository repositoryA = new RedisAbuseWindowRepository(redis);
        RedisAbuseWindowRepository repositoryB = new RedisAbuseWindowRepository(redis);
        gatewayA = service(repositoryA);
        gatewayB = service(repositoryB);
    }

    @Test
    void fewerThanThresholdAndLargeSingleWindowBurstDoNotBlock() {
        String client = ClientKeyHasher.hash("ip:198.51.100.10");

        assertThat(record(gatewayA, client, 2))
                .allMatch(decision -> decision.type() == AbuseDecision.Type.NONE);

        var decisions = record(gatewayA, client, 98);

        assertThat(decisions)
                .filteredOn(decision -> decision.type() == AbuseDecision.Type.ABUSIVE_WINDOW)
                .hasSize(1)
                .first()
                .extracting(AbuseDecision::abusiveWindowCount)
                .isEqualTo(1);
        assertThat(decisions).noneMatch(decision -> decision.type() == AbuseDecision.Type.WOULD_BLOCK);
        assertThat(redis.hasKey(RedisAbuseWindowRepository.blockKey(client)).block()).isFalse();
    }

    @Test
    void threeAdjacentAbusiveWindowsWouldBlockOnlyInShadow() {
        String client = ClientKeyHasher.hash("ip:198.51.100.11");

        assertThat(abuseCurrentWindow(gatewayA, client).abusiveWindowCount()).isEqualTo(1);
        clock.advanceSeconds(10);
        assertThat(abuseCurrentWindow(gatewayB, client).abusiveWindowCount()).isEqualTo(2);
        clock.advanceSeconds(10);
        AbuseDecision third = abuseCurrentWindow(gatewayA, client);

        assertThat(third.type()).isEqualTo(AbuseDecision.Type.WOULD_BLOCK);
        assertThat(redis.hasKey(RedisAbuseWindowRepository.blockKey(client)).block()).isFalse();
    }

    @Test
    void gapResetsSequenceAndTwoWindowsNeverBlock() {
        String client = ClientKeyHasher.hash("ip:198.51.100.12");

        assertThat(abuseCurrentWindow(gatewayA, client).abusiveWindowCount()).isEqualTo(1);
        clock.advanceSeconds(20);
        assertThat(abuseCurrentWindow(gatewayB, client).abusiveWindowCount()).isEqualTo(1);
        clock.advanceSeconds(10);
        assertThat(abuseCurrentWindow(gatewayA, client).abusiveWindowCount()).isEqualTo(2);

        assertThat(redis.hasKey(RedisAbuseWindowRepository.blockKey(client)).block()).isFalse();
    }

    @Test
    void enforceCreatesSharedTtlBlockAndKeepsOtherClientIndependent() throws InterruptedException {
        properties.setMode(IpBlockingProperties.Mode.ENFORCE);
        String clientA = ClientKeyHasher.hash("ip:198.51.100.20");
        String clientB = ClientKeyHasher.hash("ip:198.51.100.21");

        abuseCurrentWindow(gatewayA, clientA);
        clock.advanceSeconds(10);
        abuseCurrentWindow(gatewayB, clientA);
        clock.advanceSeconds(10);
        AbuseDecision decision = abuseCurrentWindow(gatewayA, clientA);

        assertThat(decision.type()).isEqualTo(AbuseDecision.Type.BLOCK_CREATED);
        Long ttl = gatewayBRepository().remainingBlockTtlMillis(clientA).block();
        assertThat(ttl).isBetween(55_000L, 60_000L);
        assertThat(gatewayBRepository().remainingBlockTtlMillis(clientB).block()).isEqualTo(-2L);

        Thread.sleep(1_100);
        Long decreasedTtl = gatewayBRepository().remainingBlockTtlMillis(clientA).block();
        assertThat(decreasedTtl).isLessThan(ttl - 900);

        IpBlockingMetrics metrics = new IpBlockingMetrics(new SimpleMeterRegistry(), properties);
        TemporaryIpBlockFilter gatewayBFilter = new TemporaryIpBlockFilter(
                new ClientIpKeyResolver(), gatewayBRepository(), properties, metrics);
        AtomicBoolean blockedBackendCalled = new AtomicBoolean();
        MockServerWebExchange blockedExchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/auth/login")
                        .header(ClientIpKeyResolver.CLIENT_IP_HEADER, "198.51.100.20"));
        gatewayBFilter.filter(blockedExchange, ignored -> {
            blockedBackendCalled.set(true);
            return Mono.empty();
        }).block(Duration.ofSeconds(5));

        assertThat(blockedBackendCalled).isFalse();
        assertThat(blockedExchange.getResponse().getStatusCode().value()).isEqualTo(429);
        long retryAfter = Long.parseLong(
                blockedExchange.getResponse().getHeaders().getFirst("Retry-After"));
        long ttlAfterResponse = gatewayBRepository().remainingBlockTtlMillis(clientA).block();
        assertThat(retryAfter).isBetween(
                Math.max(1, (ttlAfterResponse + 999) / 1000),
                (decreasedTtl + 999) / 1000);

        AtomicBoolean otherBackendCalled = new AtomicBoolean();
        MockServerWebExchange otherExchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/auth/login")
                        .header(ClientIpKeyResolver.CLIENT_IP_HEADER, "198.51.100.21"));
        gatewayBFilter.filter(otherExchange, ignored -> {
            otherBackendCalled.set(true);
            return Mono.empty();
        }).block(Duration.ofSeconds(5));
        assertThat(otherBackendCalled).isTrue();
    }

    @Test
    void concurrentReplicasCountOneAbusiveWindowOnly() {
        String client = ClientKeyHasher.hash("ip:198.51.100.30");

        var decisions = Flux.range(0, 100)
                .flatMap(index -> (index % 2 == 0 ? gatewayA : gatewayB)
                        .recordRateLimitRejection(client), 32)
                .collectList()
                .block(Duration.ofSeconds(10));

        assertThat(decisions)
                .filteredOn(decision -> decision.type() == AbuseDecision.Type.ABUSIVE_WINDOW)
                .hasSize(1);
        assertThat(redis.hasKey(RedisAbuseWindowRepository.blockKey(client)).block()).isFalse();
    }

    @Test
    void ttlExpiresAutomaticallyAndOldSequenceDoesNotImmediatelyReblock() throws InterruptedException {
        properties = properties(IpBlockingProperties.Mode.ENFORCE, Duration.ofSeconds(2));
        gatewayA = service(new RedisAbuseWindowRepository(redis));
        gatewayB = service(new RedisAbuseWindowRepository(redis));
        String client = ClientKeyHasher.hash("ip:198.51.100.40");

        abuseCurrentWindow(gatewayA, client);
        clock.advanceSeconds(10);
        abuseCurrentWindow(gatewayB, client);
        clock.advanceSeconds(10);
        assertThat(abuseCurrentWindow(gatewayA, client).type())
                .isEqualTo(AbuseDecision.Type.BLOCK_CREATED);

        Thread.sleep(2_100);

        assertThat(gatewayBRepository().remainingBlockTtlMillis(client).block()).isEqualTo(-2L);
        clock.advanceSeconds(10);
        assertThat(abuseCurrentWindow(gatewayB, client))
                .extracting(AbuseDecision::type, AbuseDecision::abusiveWindowCount)
                .containsExactly(AbuseDecision.Type.ABUSIVE_WINDOW, 1);
    }

    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void nativeRedisRateLimiter429IsObservedAndIncrementsWindowState() {
        String rawClientKey = "ip:198.51.100.50";
        String safeClientKey = ClientKeyHasher.hash(rawClientKey);
        DefaultRedisScript<List<Long>> rateLimitScript = new DefaultRedisScript<>();
        rateLimitScript.setScriptSource(new ResourceScriptSource(
                new ClassPathResource("META-INF/scripts/request_rate_limiter.lua")));
        rateLimitScript.setResultType((Class) List.class);
        RedisRateLimiter redisRateLimiter = new RedisRateLimiter(
                redis, rateLimitScript, mock(ConfigurationService.class));
        redisRateLimiter.getConfig().put("auth", new RedisRateLimiter.Config()
                .setReplenishRate(1)
                .setBurstCapacity(1));

        ClientIpKeyResolver resolver = new ClientIpKeyResolver();
        RequestRateLimiterGatewayFilterFactory.Config rateLimitConfig =
                new RequestRateLimiterGatewayFilterFactory.Config()
                        .setRateLimiter(redisRateLimiter)
                        .setKeyResolver(resolver);
        rateLimitConfig.setRouteId("auth");
        RateLimitOutcomeFilter rateLimitFilter = new RateLimitOutcomeFilter(
                new RequestRateLimiterGatewayFilterFactory(redisRateLimiter, resolver)
                        .apply(rateLimitConfig));
        RedisAbuseWindowRepository repository = new RedisAbuseWindowRepository(redis);
        IpBlockingMetrics metrics = new IpBlockingMetrics(new SimpleMeterRegistry(), properties);
        AbuseWindowService service = new AbuseWindowService(repository, properties, metrics, clock);
        RateLimitAbuseObserver observer = new RateLimitAbuseObserver(service, properties);
        TemporaryIpBlockFilter blockFilter = new TemporaryIpBlockFilter(
                resolver, repository, properties, metrics);

        GatewayResult allowedResult = executeGatewayFilters(
                blockFilter, observer, rateLimitFilter, "198.51.100.50")
                .block(Duration.ofSeconds(5));

        assertThat(allowedResult.backendCalled()).isTrue();
        assertThat(redis.hasKey(RedisAbuseWindowRepository.windowKey(
                safeClientKey, 100)).block()).isFalse();

        var results = Flux.range(0, 3)
                .concatMap(ignored -> executeGatewayFilters(
                        blockFilter, observer, rateLimitFilter, "198.51.100.50"))
                .collectList()
                .block(Duration.ofSeconds(10));

        assertThat(results)
                .hasSize(3)
                .allSatisfy(result -> {
                    assertThat(result.backendCalled()).isFalse();
                    assertThat(result.exchange().getResponse().getStatusCode().value()).isEqualTo(429);
                    Object rejectionMarker = result.exchange().getAttribute(
                            IpBlockingExchangeAttributes.RATE_LIMIT_REJECTED);
                    assertThat(rejectionMarker).isEqualTo(Boolean.TRUE);
                });
        assertThat(redis.opsForHash()
                .get(RedisAbuseWindowRepository.sequenceKey(safeClientKey), "count").block())
                .isEqualTo("1");
    }

    private reactor.core.publisher.Mono<GatewayResult> executeGatewayFilters(
            TemporaryIpBlockFilter blockFilter,
            RateLimitAbuseObserver observer,
            RateLimitOutcomeFilter rateLimitFilter,
            String clientIp) {
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/auth/login")
                        .header(ClientIpKeyResolver.CLIENT_IP_HEADER, clientIp)
                        .remoteAddress(new InetSocketAddress("10.0.0.5", 12345))
                        .build());
        AtomicBoolean backendCalled = new AtomicBoolean();
        return blockFilter.filter(exchange, first ->
                        observer.filter(first, second ->
                                rateLimitFilter.filter(second, third -> {
                                    backendCalled.set(true);
                                    return reactor.core.publisher.Mono.empty();
                                })))
                .then(Mono.fromSupplier(() -> new GatewayResult(exchange, backendCalled.get())));
    }

    private AbuseDecision abuseCurrentWindow(AbuseWindowService service, String client) {
        return record(service, client, 3).get(2);
    }

    private java.util.List<AbuseDecision> record(
            AbuseWindowService service, String client, int count) {
        return Flux.range(0, count)
                .concatMap(ignored -> service.recordRateLimitRejection(client))
                .collectList()
                .block(Duration.ofSeconds(10));
    }

    private AbuseWindowService service(RedisAbuseWindowRepository repository) {
        return new AbuseWindowService(repository, properties,
                new IpBlockingMetrics(new SimpleMeterRegistry(), properties), clock);
    }

    private RedisAbuseWindowRepository gatewayBRepository() {
        return new RedisAbuseWindowRepository(redis);
    }

    private IpBlockingProperties properties(
            IpBlockingProperties.Mode mode, Duration blockDuration) {
        IpBlockingProperties result = new IpBlockingProperties();
        result.setMode(mode);
        result.getWindow().setDuration(Duration.ofSeconds(10));
        result.getWindow().setRateLimit429Threshold(3);
        result.getWindow().setAbusiveWindowsRequired(3);
        result.getBlock().setDuration(blockDuration);
        result.validate();
        return result;
    }

    private static int availablePort() throws IOException {
        try (ServerSocket socket = new ServerSocket(0)) {
            return socket.getLocalPort();
        }
    }

    private record GatewayResult(MockServerWebExchange exchange, boolean backendCalled) {
    }
}
