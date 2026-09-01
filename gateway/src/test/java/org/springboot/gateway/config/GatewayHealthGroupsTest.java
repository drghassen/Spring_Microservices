package org.springboot.gateway.config;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "spring.data.redis.port=1",
                "spring.data.redis.connect-timeout=100ms",
                "spring.data.redis.timeout=100ms"
        }
)
class GatewayHealthGroupsTest {

    @Autowired
    private TestRestTemplate restTemplate;

    @Test
    void keepsReadinessUpWhileReportingRedisDownSeparately() {
        ResponseEntity<JsonNode> readiness = restTemplate.getForEntity(
                "/actuator/health/readiness", JsonNode.class);
        ResponseEntity<JsonNode> redis = restTemplate.getForEntity(
                "/actuator/health/redis", JsonNode.class);

        assertThat(readiness.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(readiness.getBody()).isNotNull();
        assertThat(readiness.getBody().path("status").asText()).isEqualTo("UP");

        assertThat(redis.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        assertThat(redis.getBody()).isNotNull();
        assertThat(redis.getBody().path("status").asText()).isEqualTo("DOWN");
    }
}
