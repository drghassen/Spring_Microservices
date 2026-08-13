package org.springboot.paymentservice.services;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springboot.paymentservice.mapper.PaymentMapper;
import org.springboot.paymentservice.payment.Payment;
import org.springboot.paymentservice.payment.PaymentMethod;
import org.springboot.paymentservice.payment.PaymentRequest;
import org.springboot.paymentservice.user.UserApp;
import org.springboot.paymentservice.repository.PaymentRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PaymentServiceTests {

    @Mock
    private PaymentRepository repository;
    @Mock
    private PaymentMapper mapper;

    @Test
    void createPaymentShouldReturnPersistedPaymentId() {
        var service = new PaymentService(repository, mapper);
        var request = new PaymentRequest(
                11,
                59.99,
                PaymentMethod.PAYPAL,
                77,
                "REF-77",
                new UserApp("u1", "Alice", "alice", "alice@example.com")
        );
        var payment = Payment.builder()
                .id(123)
                .amount(59.99)
                .paymentMethod(PaymentMethod.PAYPAL)
                .orderId(77)
                .build();

        when(mapper.toPayment(request)).thenReturn(payment);
        when(repository.save(payment)).thenReturn(payment);

        Integer result = service.createPayment(request);

        assertThat(result).isEqualTo(123);
    }
}
