package org.springboot.orderservice;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;

import static org.junit.jupiter.api.Assertions.assertNotNull;

@SpringBootTest(properties = {
        "spring.cloud.config.enabled=false",
        "eureka.client.enabled=false",
        "application.config.games-url=http://localhost:8222/api/v1/games",
        "application.config.library-url=http://localhost:8222/api/v1/library",
        "application.config.payment-url=http://localhost:8222/api/v1/payments",
        "application.config.user-url=http://localhost:8222/api/v1/users"
})
class OrderServiceApplicationTests {

    @Autowired
    private ApplicationContext applicationContext;

    @Test
    void contextLoads() {
        assertNotNull(applicationContext);
    }
}
