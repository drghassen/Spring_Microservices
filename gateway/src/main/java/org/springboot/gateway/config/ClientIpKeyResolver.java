package org.springboot.gateway.config;

import io.netty.util.NetUtil;
import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.util.List;
import java.util.Optional;

@Component("clientIpKeyResolver")
public class ClientIpKeyResolver implements KeyResolver {

    public static final String CLIENT_IP_HEADER = "X-Client-IP";
    public static final String RESOLVED_CLIENT_KEY_ATTRIBUTE =
            ClientIpKeyResolver.class.getName() + ".resolvedClientKey";
    private static final String UNKNOWN_CLIENT = "unknown";

    @Override
    public Mono<String> resolve(ServerWebExchange exchange) {
        String cachedKey = exchange.getAttribute(RESOLVED_CLIENT_KEY_ATTRIBUTE);
        if (cachedKey != null) {
            return Mono.just(cachedKey);
        }

        String resolvedKey = "ip:" + resolveClientIp(exchange);
        exchange.getAttributes().put(RESOLVED_CLIENT_KEY_ATTRIBUTE, resolvedKey);
        return Mono.just(resolvedKey);
    }

    private String resolveClientIp(ServerWebExchange exchange) {
        Optional<String> trustedClientAddress = trustedClientAddress(exchange.getRequest().getHeaders());
        if (trustedClientAddress.isPresent()) {
            return trustedClientAddress.get();
        }

        return remoteAddress(exchange.getRequest().getRemoteAddress()).orElse(UNKNOWN_CLIENT);
    }

    /**
     * X-Client-IP is accepted only as a single IP literal. The trusted Nginx
     * caller overwrites this header after selecting the address appended by the
     * external ACA ingress. X-Forwarded-For is deliberately not consulted here.
     */
    private Optional<String> trustedClientAddress(HttpHeaders headers) {
        List<String> values = headers.getOrEmpty(CLIENT_IP_HEADER);
        if (values.size() != 1) {
            return Optional.empty();
        }
        return normalizeIpLiteral(values.get(0));
    }

    private Optional<String> remoteAddress(InetSocketAddress remoteAddress) {
        if (remoteAddress == null || remoteAddress.getAddress() == null) {
            return Optional.empty();
        }
        return Optional.of(normalize(remoteAddress.getAddress()));
    }

    private Optional<String> normalizeIpLiteral(String candidate) {
        if (candidate == null) {
            return Optional.empty();
        }

        String trimmedCandidate = candidate.trim();
        if (trimmedCandidate.isEmpty() || trimmedCandidate.contains("%")) {
            return Optional.empty();
        }

        InetAddress address = NetUtil.createInetAddressFromIpAddressString(trimmedCandidate);
        return Optional.ofNullable(address).map(this::normalize);
    }

    private String normalize(InetAddress address) {
        return NetUtil.toAddressString(address);
    }
}
