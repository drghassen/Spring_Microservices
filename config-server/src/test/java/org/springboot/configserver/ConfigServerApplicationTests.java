package org.springboot.configserver;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.boot.test.web.client.TestRestTemplate;

import java.io.IOException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertNotNull;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ConfigServerApplicationTests {

    @Autowired
    private ApplicationContext applicationContext;

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void contextLoads() {
        assertNotNull(applicationContext);
    }

    @Test
    void servesPostgreSqlAndMongoAcaProfilesWithoutResolvingSecrets() throws IOException {
        JsonNode gamesAca = configFor("games-service");
        JsonNode userAca = configFor("user-service");
        JsonNode libraryAca = configFor("library-service");

        assertThat(property(gamesAca, "spring.datasource.url")).isEqualTo("${DB_URL}?sslmode=require");
        assertThat(property(gamesAca, "spring.flyway.enabled")).isEqualTo("true");
        assertThat(property(gamesAca, "spring.jpa.hibernate.ddl-auto")).isEqualTo("validate");
        assertThat(property(userAca, "spring.data.mongodb.uri")).isEqualTo("${MONGO_URI}");
        assertThat(property(userAca, "spring.data.mongodb.database")).isEqualTo("users");
        assertThat(property(libraryAca, "spring.data.mongodb.database")).isEqualTo("library");
    }

    @Test
    void servesMandatoryRedisHostAndConfigurableRateLimitForGatewayAca() throws IOException {
        JsonNode gatewayAca = configFor("gateway");

        assertThat(property(gatewayAca, "spring.data.redis.host")).isEqualTo("${REDIS_HOST}");
        assertThat(property(gatewayAca, "spring.data.redis.port")).isEqualTo("${REDIS_PORT:6379}");
        assertThat(property(gatewayAca, "rate-limit.auth.replenish-rate"))
                .isEqualTo("${RATE_LIMIT_AUTH_REPLENISH_RATE:5}");
        assertThat(property(gatewayAca, "rate-limit.auth.burst-capacity"))
                .isEqualTo("${RATE_LIMIT_AUTH_BURST_CAPACITY:10}");
        assertThat(property(gatewayAca, "ip-blocking.mode"))
                .isEqualTo("${IP_BLOCKING_MODE:SHADOW}");
        assertThat(property(gatewayAca, "ip-blocking.window.duration"))
                .isEqualTo("${IP_BLOCKING_WINDOW_SECONDS:10}s");
        assertThat(property(gatewayAca, "ip-blocking.window.rate-limit-429-threshold"))
                .isEqualTo("${IP_BLOCKING_429_THRESHOLD:3}");
        assertThat(property(gatewayAca, "ip-blocking.window.abusive-windows-required"))
                .isEqualTo("${IP_BLOCKING_WINDOWS_REQUIRED:3}");
        assertThat(property(gatewayAca, "ip-blocking.block.duration"))
                .isEqualTo("${IP_BLOCKING_DURATION_SECONDS:60}s");
    }

    private JsonNode configFor(String applicationName) throws IOException {
        String response = restTemplate.getForObject("/{application}/aca", String.class, applicationName);

        return objectMapper.readTree(response);
    }

    private String property(JsonNode environment, String name) {
        for (JsonNode propertySource : environment.path("propertySources")) {
            JsonNode value = propertySource.path("source").get(name);
            if (value != null) {
                return value.asText();
            }
        }

        throw new AssertionError("Missing Config Server property: " + name);
    }
}
