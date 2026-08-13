package org.springboot.orderservice.games;
import jakarta.validation.constraints.NotNull;

public record PurchaseRequest (
        @NotNull(message = "Game is mandatory")
        Integer gameId
){
}
