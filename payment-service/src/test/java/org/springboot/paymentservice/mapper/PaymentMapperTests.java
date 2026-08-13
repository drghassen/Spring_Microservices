package org.springboot.paymentservice.mapper;

import org.junit.jupiter.api.Test;
import org.springboot.paymentservice.payment.PaymentMethod;
import org.springboot.paymentservice.payment.PaymentRequest;
import org.springboot.paymentservice.user.UserApp;

import static org.assertj.core.api.Assertions.assertThat;

class PaymentMapperTests {

    private final PaymentMapper mapper = new PaymentMapper();

    @Test
    void toPaymentShouldMapFields() {
        var request = new PaymentRequest(
                11,
                59.99,
                PaymentMethod.PAYPAL,
                77,
                "REF-77",
                new UserApp("u1", "Alice", "alice", "alice@example.com")
        );

        var payment = mapper.toPayment(request);

        assertThat(payment).isNotNull();
        assertThat(payment.getId()).isEqualTo(11);
        assertThat(payment.getAmount()).isEqualTo(59.99);
        assertThat(payment.getPaymentMethod()).isEqualTo(PaymentMethod.PAYPAL);
        assertThat(payment.getOrderId()).isEqualTo(77);
    }

    @Test
    void toPaymentShouldReturnNullWhenRequestIsNull() {
        assertThat(mapper.toPayment(null)).isNull();
    }
}
