package org.springboot.orderservice.services;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springboot.orderservice.games.GameClient;
import org.springboot.orderservice.games.PurchaseRequest;
import org.springboot.orderservice.games.PurchaseResponse;
import org.springboot.orderservice.library.LibraryClient;
import org.springboot.orderservice.library.PurchaseLibrary;
import org.springboot.orderservice.mapper.OrderMapper;
import org.springboot.orderservice.order.OrderApp;
import org.springboot.orderservice.order.OrderRequest;
import org.springboot.orderservice.order.PaymentMethod;
import org.springboot.orderservice.order.ResponseOrder;
import org.springboot.orderservice.payment.PaymentClient;
import org.springboot.orderservice.repository.OrderRepository;
import org.springboot.orderservice.user.UserClient;
import org.springboot.orderservice.user.UserResponse;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class OrderServiceTests {

    @Mock
    private OrderRepository repository;
    @Mock
    private OrderMapper mapper;
    @Mock
    private UserClient userClient;
    @Mock
    private PaymentClient paymentClient;
    @Mock
    private GameClient gameClient;
    @Mock
    private OrderLineService orderLineService;
    @Mock
    private LibraryClient libraryClient;

    @InjectMocks
    private OrderService orderService;

    @Test
    void createOrderShouldShortCircuitWhenGameAlreadyExistsInLibrary() {
        var request = new OrderRequest(
                1,
                "REF-1",
                PaymentMethod.VISA,
                "alice",
                List.of(new PurchaseRequest(10))
        );
        var token = "Bearer token";
        var library = new PurchaseLibrary(
                List.of(new PurchaseResponse(10, "Game", "Desc", 12.0)),
                "alice"
        );

        when(libraryClient.getLibrary("alice", token)).thenReturn(library);
        when(userClient.findUserByUsername("alice", token))
                .thenReturn(Optional.of(new UserResponse("u1", "Alice", "alice", "alice@example.com")));

        ResponseOrder result = orderService.createOrder(request, token);

        assertThat(result.msg()).isEqualTo("Game already exists with id: 10");
        verify(gameClient, never()).purchaseGames(any(), any());
        verify(repository, never()).save(any());
        verify(paymentClient, never()).requestOrderPayment(any(), any());
        verify(orderLineService, never()).saveOrderLine(any());
    }

    @Test
    void createOrderShouldPersistOrderAndRelatedData() {
        var request = new OrderRequest(
                1,
                "REF-1",
                PaymentMethod.VISA,
                "alice",
                List.of(new PurchaseRequest(10), new PurchaseRequest(20))
        );
        var token = "Bearer token";
        var library = new PurchaseLibrary(List.of(), "alice");
        var user = new UserResponse("u1", "Alice", "alice", "alice@example.com");
        var purchasedGames = List.of(
                new PurchaseResponse(10, "Game A", "Desc", 12.0),
                new PurchaseResponse(20, "Game B", "Desc", 18.5)
        );
        var order = OrderApp.builder()
                .id(99)
                .reference("REF-1")
                .paymentMethod(PaymentMethod.VISA)
                .username("alice")
                .totalAmount(30.5)
                .build();

        when(libraryClient.getLibrary("alice", token)).thenReturn(library);
        when(userClient.findUserByUsername("alice", token)).thenReturn(Optional.of(user));
        when(gameClient.purchaseGames(request.games(), token)).thenReturn(purchasedGames);
        when(mapper.toOrder(request, 30.5)).thenReturn(order);
        when(repository.save(order)).thenReturn(order);

        ResponseOrder result = orderService.createOrder(request, token);

        assertThat(result.msg()).isEqualTo("Order created with ID: 99");
        verify(repository).save(order);
        verify(orderLineService).saveOrderLine(new org.springboot.orderservice.orderline.OrderLineRequestWithoutId(99, 10));
        verify(orderLineService).saveOrderLine(new org.springboot.orderservice.orderline.OrderLineRequestWithoutId(99, 20));
        verify(paymentClient).requestOrderPayment(any(), eq(token));
        verify(libraryClient).purchaseLibrary(any(PurchaseLibrary.class), eq(token));
    }
}
