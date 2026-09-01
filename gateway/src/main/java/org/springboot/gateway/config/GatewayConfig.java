package org.springboot.gateway.config;

import org.springboot.gateway.filter.JwtAuthenticationFilter;
import org.springboot.gateway.filter.RateLimitAbuseObserver;
import org.springboot.gateway.filter.RateLimitOutcomeFilter;
import org.springboot.gateway.filter.RoleAssignmentFilter;
import org.springboot.gateway.filter.TemporaryIpBlockFilter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;


@Configuration
public class GatewayConfig {
    private final JwtAuthenticationFilter filter;
    private final TemporaryIpBlockFilter temporaryIpBlockFilter;
    private final RateLimitAbuseObserver rateLimitAbuseObserver;
    private final RateLimitOutcomeFilter authRateLimitOutcomeFilter;
    
        //VARIABLES
        @Value("${roles.admin}")
        private String roleAdmin;

        @Value("${roles.user}")
        private String roleUser;

        @Value("${services.user-service.name}")
        private String userService;

        @Value("${services.user-service.uri}")
        private String uriUserService;

        @Value("${services.payment-service.name}")
        private String paymentService;

        @Value("${services.payment-service.uri}")
        private String uriPaymentService;

        @Value("${services.order-service.name}")
        private String orderService;

        @Value("${services.order-service.uri}")
        private String uriOrderService;

        @Value("${services.games-service.name}")
        private String gamesService;

        @Value("${services.games-service.uri}")
        private String uriGamesService;

        @Value("${services.library-service.name}")
        private String libraryService;

        @Value("${services.library-service.uri}")
        private String uriLibraryService;



    public GatewayConfig(
            JwtAuthenticationFilter filter,
            TemporaryIpBlockFilter temporaryIpBlockFilter,
            RateLimitAbuseObserver rateLimitAbuseObserver,
            RateLimitOutcomeFilter authRateLimitOutcomeFilter) {
        this.filter = filter;
        this.temporaryIpBlockFilter = temporaryIpBlockFilter;
        this.rateLimitAbuseObserver = rateLimitAbuseObserver;
        this.authRateLimitOutcomeFilter = authRateLimitOutcomeFilter;
    }

    @Bean
    public RouteLocator routes(RouteLocatorBuilder builder) {
        return builder.routes()
                // USER SERVICE ROUTES
                .route(userService, r -> r.path("/api/v1/users/**")
                        .filters(f -> f
                                .filter(new RoleAssignmentFilter(List.of(roleAdmin, roleUser)))
                                .filter(filter))
                        .uri(uriUserService))

                .route(userService, r -> r.path("/api/v1/auth/**")
                        .filters(f -> f
                                .filter(temporaryIpBlockFilter)
                                .filter(rateLimitAbuseObserver)
                                .filter(authRateLimitOutcomeFilter))
                        .uri(uriUserService))

                .route(userService, r -> r.path("/api/v1/user/admin/**")
                        .filters(f -> f
                                .filter(new RoleAssignmentFilter(List.of(roleAdmin)))
                                .filter(filter))
                        .uri(uriUserService))

                //SWAGGER
                .route(userService, r -> r.path("/users/swagger-ui/**")
                        .uri(uriUserService))
                .route(userService, r -> r.path("/users/v3/api-docs/**")
                        .uri(uriUserService)) // Forward to the user-service

                //GAMES SERVICE ROUTES
                .route(gamesService, r -> r.path("/api/v1/games/purchase")
                        .filters(f -> f
                                .filter(new RoleAssignmentFilter(List.of(roleAdmin, roleUser)))
                                .filter(filter))
                        .uri(uriGamesService))

                .route(gamesService, r -> r.path("/api/v1/games")
                        .uri(uriGamesService))

                .route(gamesService, r -> r.path("/api/v1/games/{gameId}/image")
                        .uri(uriGamesService))

                .route(gamesService, r -> r.path("/api/v1/games/pagination")
                        .uri(uriGamesService))

                .route(gamesService, r -> r.path("/api/v1/games/{games-id}")
                        .uri(uriGamesService))

                .route(gamesService, r -> r.path("/api/v1/game/admin/**")
                        .filters(f -> f
                                .filter(new RoleAssignmentFilter(List.of(roleAdmin)))
                                .filter(filter))
                        .uri(uriGamesService))

                .route(gamesService, r -> r.path("/api/v1/category/admin/**")
                        .filters(f -> f
                                .filter(new RoleAssignmentFilter(List.of(roleAdmin)))
                                .filter(filter))
                        .uri(uriGamesService))

                //SWAGGER
                .route(gamesService, r -> r.path("/games/swagger-ui/**")
                        .uri(uriGamesService))
                .route(gamesService, r -> r.path("/games/v3/api-docs/**")
                        .uri(uriGamesService)) // Forward to the user-service

                //ORDER SERVICE ROUTES
                .route(orderService, r -> r.path("/api/v1/orders/**")
                        .filters(f -> f
                                .filter(new RoleAssignmentFilter(List.of(roleAdmin, roleUser)))
                                .filter(filter))
                        .uri(uriOrderService))


                .route(orderService, r -> r.path("/api/v1/order/admin/**")
                        .filters(f -> f
                                .filter(new RoleAssignmentFilter(List.of(roleAdmin)))
                                .filter(filter))
                        .uri(uriOrderService))


                .route(orderService, r -> r.path("/api/v1/order-lines/**")
                        .filters(f -> f
                                .filter(new RoleAssignmentFilter(List.of(roleUser,roleAdmin)))
                                .filter(filter))
                        .uri(uriOrderService))

                //SWAGGER
                .route(orderService, r -> r.path("/order/swagger-ui/**")
                        .uri(uriOrderService))
                .route(orderService, r -> r.path("/order/v3/api-docs/**")
                        .uri(uriOrderService)) // Forward to the user-service

                //PAYMENTS SERVICE ROUTES
                .route(paymentService, r -> r.path("/api/v1/payments/**")
                        .filters(f -> f
                                .filter(new RoleAssignmentFilter(List.of(roleAdmin, roleUser)))
                                .filter(filter))
                        .uri(uriPaymentService))

                //SWAGGER
                .route(paymentService, r -> r.path("/payment/swagger-ui/**")
                        .uri(uriPaymentService))
                .route(paymentService, r -> r.path("/payment/v3/api-docs/**")
                        .uri(uriPaymentService)) // Forward to the user-service


                //LIBRARY SERVICE ROUTES
                .route(libraryService, r -> r.path("/api/v1/library/**")
                        .filters(f -> f
                                .filter(new RoleAssignmentFilter(List.of(roleAdmin, roleUser)))
                                .filter(filter))
                        .uri(uriLibraryService))

                //SWAGGER
                .route(libraryService, r -> r.path("/library/swagger-ui/**")
                        .uri(uriLibraryService))
                .route(libraryService, r -> r.path("/library/v3/api-docs/**")
                        .uri(uriLibraryService)) // Forward to the user-service


                .build();
    }




}
