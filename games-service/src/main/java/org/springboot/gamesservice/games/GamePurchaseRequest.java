package org.springboot.gamesservice.games;

import jakarta.validation.constraints.NotNull;

public record GamePurchaseRequest(
        @NotNull(message = "Game is mandatory")
        Integer gameId
) {
}
