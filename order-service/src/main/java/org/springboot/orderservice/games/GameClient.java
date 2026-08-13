package org.springboot.orderservice.games;
import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;

import java.util.List;

@FeignClient(
        name = "games-service",
        url = "${application.config.games-url}"
)
public interface GameClient {
    @PostMapping("/purchase")
    List<PurchaseResponse> purchaseGames(@RequestBody List<PurchaseRequest> requestBody, @RequestHeader("Authorization") String token);

}
