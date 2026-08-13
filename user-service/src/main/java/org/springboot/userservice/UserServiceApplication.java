package org.springboot.userservice;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springboot.userservice.config.ApplicationConfig;
import org.springboot.userservice.repository.UserRepo;
import org.springboot.userservice.user.Role;
import org.springboot.userservice.user.UserApp;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.openfeign.EnableFeignClients;
import org.springframework.context.annotation.Bean;

import java.util.UUID;

@EnableFeignClients
@SpringBootApplication
@RequiredArgsConstructor
@Slf4j
public class UserServiceApplication {

	private static final String ADMIN_USERNAME = "admin";

	//Building ADMIN USER
	private final ApplicationConfig securityConfiguration;

	@Value("${admin.password:${ADMIN_PASSWORD:}}")
	private String adminPassword;

	@Bean
	CommandLineRunner commandLineRunner(UserRepo userRepository) {
		return args -> {
			try {
				var adminExists = userRepository.findByUsername(ADMIN_USERNAME);
				if (adminExists.isPresent()) {
					log.info("{} already exists", ADMIN_USERNAME);
					return;
				}

				UserApp u1 = UserApp.builder()
					.name(ADMIN_USERNAME)
					.email("admin@admin.com")
					.username(ADMIN_USERNAME)
					.id(UUID.randomUUID().toString())
					.password(securityConfiguration.passwordEncoder().encode(adminPassword))
					.role(Role.ADMIN)
					.build();
				userRepository.save(u1);
			} catch (Exception ex) {
				log.warn("Skipping admin bootstrap because the user repository is unavailable: {}", ex.getMessage());
			}
		};
	}

	public static void main(String[] args) {
		SpringApplication.run(UserServiceApplication.class, args);
	}

}
