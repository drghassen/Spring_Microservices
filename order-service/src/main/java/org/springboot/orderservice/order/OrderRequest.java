package org.springboot.orderservice.order;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonInclude.Include;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import org.springboot.orderservice.games.PurchaseRequest;

import java.util.List;


@JsonInclude(Include.NON_EMPTY)
public record OrderRequest(
        Integer id,
        String reference,
        @NotNull(message = "Payment method should be precised")
        PaymentMethod paymentMethod,
        String username,
        @NotEmpty(message = "You should at least purchase one game")
        List<PurchaseRequest> games

) {
}
