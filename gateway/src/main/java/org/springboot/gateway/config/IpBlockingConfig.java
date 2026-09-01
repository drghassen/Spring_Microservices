package org.springboot.gateway.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

@Configuration
@EnableConfigurationProperties(IpBlockingProperties.class)
public class IpBlockingConfig {

    @Bean
    Clock ipBlockingClock(IpBlockingProperties properties) {
        properties.validate();
        return Clock.systemUTC();
    }
}
