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
