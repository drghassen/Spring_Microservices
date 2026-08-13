package org.springboot.orderservice.mapper;

import org.junit.jupiter.api.Test;
import org.springboot.orderservice.games.PurchaseRequest;
import org.springboot.orderservice.order.OrderRequest;
import org.springboot.orderservice.order.PaymentMethod;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class OrderMapperTests {

    private final OrderMapper mapper = new OrderMapper();

    @Test
    void toOrderShouldMapOrderFieldsAndAmount() {
        var request = new OrderRequest(
                7,
                "REF-7",
                PaymentMethod.VISA,
                "alice",
                List.of(new PurchaseRequest(1), new PurchaseRequest(2))
        );

        var result = mapper.toOrder(request, 42.5);

        assertThat(result).isNotNull();
        assertThat(result.getId()).isEqualTo(7);
        assertThat(result.getReference()).isEqualTo("REF-7");
        assertThat(result.getPaymentMethod()).isEqualTo(PaymentMethod.VISA);
        assertThat(result.getUsername()).isEqualTo("alice");
        assertThat(result.getTotalAmount()).isEqualTo(42.5);
    }

    @Test
    void toOrderShouldReturnNullWhenRequestIsNull() {
        assertThat(mapper.toOrder(null, 10.0)).isNull();
    }
}
