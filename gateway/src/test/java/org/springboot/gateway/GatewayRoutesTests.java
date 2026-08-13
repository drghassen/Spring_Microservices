package org.springboot.gateway;

import org.junit.jupiter.api.Test;
import org.springboot.gateway.config.GatewayConfig;
import org.springboot.gateway.filter.RoleAssignmentFilter;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
class GatewayRoutesTests {

    @Autowired
    private GatewayConfig gatewayConfig;

    @Autowired
    private RouteLocatorBuilder routeLocatorBuilder;

    @Test
    void shouldDefineRoutesCorrectly() {

        // Act
        RouteLocator routeLocator = gatewayConfig.routes(routeLocatorBuilder);

        // Assert
        assertThat(routeLocator).isNotNull();

        var routes = routeLocator.getRoutes().collectList().block();

        var securedRoutes = routes.stream()
                .filter(route -> route.getFilters().stream()
                        .anyMatch(filter -> filter.toString()
                                .contains(RoleAssignmentFilter.class.getSimpleName())))
                .toList();

        assertThat(securedRoutes)
                .hasSize(10)
                .extracting(route -> route.getPredicate().toString())
                .containsExactlyInAnyOrder(
                        "Paths: [/api/v1/users/**], match trailing slash: true",
                        "Paths: [/api/v1/user/admin/**], match trailing slash: true",
                        "Paths: [/api/v1/games/purchase], match trailing slash: true",
                        "Paths: [/api/v1/game/admin/**], match trailing slash: true",
                        "Paths: [/api/v1/category/admin/**], match trailing slash: true",
                        "Paths: [/api/v1/orders/**], match trailing slash: true",
                        "Paths: [/api/v1/order/admin/**], match trailing slash: true",
                        "Paths: [/api/v1/order-lines/**], match trailing slash: true",
                        "Paths: [/api/v1/payments/**], match trailing slash: true",
                        "Paths: [/api/v1/library/**], match trailing slash: true"
                );
    }
}
