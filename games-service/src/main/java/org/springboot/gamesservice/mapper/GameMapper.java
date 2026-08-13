package org.springboot.gamesservice.mapper;


import org.springboot.gamesservice.games.*;
import org.springframework.stereotype.Service;

@Service

public class GameMapper {
    public GamesApp toGame(GamesRequest request) {
        return GamesApp.builder()
                .id(request.id())
                .name(request.name())
                .description(request.description())
                .avaiblity(request.avaiblity())
                .price(request.price())
                .build();
    }

    public GamePurchaseResponse toGamePurchaseResponse(GamesApp game) {
        return new GamePurchaseResponse(
                game.getId(),
                game.getName(),
                game.getDescription(),
                game.getPrice()
        );
    }
}
