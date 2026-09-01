package org.springboot.gateway.config;

import org.junit.jupiter.api.Test;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;

import java.net.InetSocketAddress;

import static org.assertj.core.api.Assertions.assertThat;

class ClientIpKeyResolverTest {

    private final ClientIpKeyResolver resolver = new ClientIpKeyResolver();

    @Test
    void shouldResolveValidIpv4ClientHeader() {
        assertThat(resolve(request("198.51.100.12", null, "10.0.0.5")))
                .isEqualTo("ip:198.51.100.12");
    }

    @Test
    void shouldNormalizeValidIpv6ClientHeader() {
        assertThat(resolve(request("2001:0db8:0:0:0:0:0:1", null, "10.0.0.5")))
                .isEqualTo("ip:2001:db8::1");
    }

    @Test
    void shouldUseRemoteAddressWhenClientHeaderIsAbsent() {
        assertThat(resolve(request(null, null, "192.0.2.40")))
                .isEqualTo("ip:192.0.2.40");
    }

    @Test
    void shouldUseRemoteAddressWhenClientHeaderIsEmpty() {
        assertThat(resolve(request("   ", null, "192.0.2.41")))
                .isEqualTo("ip:192.0.2.41");
    }

    @Test
    void shouldUseRemoteAddressWhenClientHeaderIsMalformed() {
        assertThat(resolve(request("999.10.10.10", null, "192.0.2.42")))
                .isEqualTo("ip:192.0.2.42");
    }

    @Test
    void shouldRejectHostnameWithoutDnsResolution() {
        assertThat(resolve(request("attacker.example", null, "192.0.2.43")))
                .isEqualTo("ip:192.0.2.43");
    }

    @Test
    void shouldNeverUseForwardedForAsRateLimitIdentity() {
        assertThat(resolve(request(null, "1.2.3.4", "192.0.2.44")))
                .isEqualTo("ip:192.0.2.44");
    }

    @Test
    void shouldReturnDifferentKeysForDifferentTrustedIps() {
        String firstKey = resolve(request("198.51.100.20", null, "10.0.0.5"));
        String secondKey = resolve(request("198.51.100.21", null, "10.0.0.5"));

        assertThat(firstKey).isNotEqualTo(secondKey);
    }

    @Test
    void shouldReturnSameKeyForEquivalentIpv6Literals() {
        String expandedKey = resolve(request("2001:db8:0:0:0:0:0:1", null, "10.0.0.5"));
        String compressedKey = resolve(request("2001:db8::1", null, "10.0.0.5"));

        assertThat(expandedKey).isEqualTo(compressedKey);
    }

    @Test
    void shouldReturnStableUnknownKeyWithoutValidHeaderOrRemoteAddress() {
        assertThat(resolve(request("not-an-ip", null, null)))
                .isEqualTo("ip:unknown");
    }

    private String resolve(MockServerHttpRequest request) {
        return resolver.resolve(MockServerWebExchange.from(request)).block();
    }

    private MockServerHttpRequest request(String clientIp, String forwardedFor, String remoteAddress) {
        MockServerHttpRequest.BaseBuilder<?> builder = MockServerHttpRequest.get("/api/v1/auth/login");
        if (clientIp != null) {
            builder.header(ClientIpKeyResolver.CLIENT_IP_HEADER, clientIp);
        }
        if (forwardedFor != null) {
            builder.header("X-Forwarded-For", forwardedFor);
        }
        if (remoteAddress != null) {
            builder.remoteAddress(new InetSocketAddress(remoteAddress, 12345));
        }
        return builder.build();
    }
}
