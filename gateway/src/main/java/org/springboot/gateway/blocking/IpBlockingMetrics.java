package org.springboot.gateway.blocking;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springboot.gateway.config.IpBlockingProperties;
import org.springframework.stereotype.Component;

@Component
public class IpBlockingMetrics {

    private static final String ROUTE_CATEGORY = "auth";

    private final Counter abusiveWindows;
    private final Counter wouldBlock;
    private final Counter blocksCreated;
    private final Counter requestsRejected;
    private final Counter redisErrors;

    public IpBlockingMetrics(MeterRegistry registry, IpBlockingProperties properties) {
        String mode = properties.getMode().name();
        abusiveWindows = counter(registry, "ip_blocking_abusive_windows_total", mode);
        wouldBlock = counter(registry, "ip_blocking_would_block_total", mode);
        blocksCreated = counter(registry, "ip_blocking_blocks_created_total", mode);
        requestsRejected = counter(registry, "ip_blocking_requests_rejected_total", mode);
        redisErrors = counter(registry, "ip_blocking_redis_errors_total", mode);
    }

    private Counter counter(MeterRegistry registry, String name, String mode) {
        return registry.counter(name, "mode", mode, "route_category", ROUTE_CATEGORY);
    }

    public void abusiveWindow() {
        abusiveWindows.increment();
    }

    public void wouldBlock() {
        wouldBlock.increment();
    }

    public void blockCreated() {
        blocksCreated.increment();
    }

    public void requestRejected() {
        requestsRejected.increment();
    }

    public void redisError() {
        redisErrors.increment();
    }
}
