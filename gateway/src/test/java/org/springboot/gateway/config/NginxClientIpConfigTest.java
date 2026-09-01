package org.springboot.gateway.config;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

class NginxClientIpConfigTest {

    @Test
    void acaConfigShouldOverwriteCallerClientIpWithExternalIngressValue() throws IOException {
        String config = Files.readString(repositoryFile("UI_Spring/nginx.aca.conf"));

        assertThat(config)
                .contains("map $http_x_forwarded_for $aca_external_client_ip")
                .contains("proxy_set_header X-Client-IP $aca_external_client_ip;")
                .doesNotContain("proxy_set_header X-Client-IP $http_x_client_ip;");
    }

    @Test
    void dockerConfigShouldOverwriteCallerClientIpWithDirectPeerAddress() throws IOException {
        String config = Files.readString(repositoryFile("UI_Spring/nginx.conf"));

        assertThat(config)
                .contains("proxy_set_header X-Client-IP $remote_addr;")
                .doesNotContain("proxy_set_header X-Client-IP $http_x_client_ip;");
    }

    private Path repositoryFile(String relativePath) {
        Path workingDirectory = Path.of("").toAbsolutePath();
        Path repositoryRoot = Files.isDirectory(workingDirectory.resolve("UI_Spring"))
                ? workingDirectory
                : workingDirectory.getParent();
        return repositoryRoot.resolve(relativePath);
    }
}
