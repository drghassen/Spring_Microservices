package org.springboot.orderservice.services;
import jakarta.persistence.EntityNotFoundException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import lombok.RequiredArgsConstructor;
import org.springboot.orderservice.exception.BusinessException;
import org.springboot.orderservice.games.GameClient;
import org.springboot.orderservice.games.PurchaseRequest;
import org.springboot.orderservice.games.PurchaseResponse;
import org.springboot.orderservice.library.LibraryClient;
import org.springboot.orderservice.library.PurchaseLibrary;
import org.springboot.orderservice.mapper.OrderMapper;
import org.springboot.orderservice.order.OrderApp;
import org.springboot.orderservice.order.OrderRequest;
import org.springboot.orderservice.order.ResponseOrder;
import org.springboot.orderservice.orderline.OrderLineRequestWithoutId;
import org.springboot.orderservice.payment.PaymentClient;
import org.springboot.orderservice.payment.PaymentRequest;
import org.springboot.orderservice.repository.OrderRepository;
import org.springboot.orderservice.user.UserClient;
import org.springframework.stereotype.Service;
import jakarta.transaction.Transactional;
import java.util.List;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository repository;
    private final OrderMapper mapper;
    private final UserClient userClient;
    private final PaymentClient paymentClient;
    private final GameClient gameClient;
    private final OrderLineService orderLineService;
    private final LibraryClient libraryClient;
    Logger logger = LoggerFactory.getLogger(OrderService.class);

    @Transactional
    public ResponseOrder createOrder(OrderRequest request, String token) {
        double amount=0;
        var username = request.username();
        var library=libraryClient.getLibrary(username,token);
        var user = this.userClient.findUserByUsername(username,token)
                .orElseThrow(() -> new BusinessException("Cannot create order:: No user exists with the provided username"));
        if (library.games()!=null) {
            for (PurchaseRequest gamesRequest : request.games()) {
            // Check if any game in the library has the same gameId as the requested game
            for (PurchaseResponse libraryGame : library.games()) {
                if (libraryGame.gameId().equals(gamesRequest.gameId())) {
                    return new ResponseOrder("Game already exists with id: " + gamesRequest.gameId());
                }
            }
        }}


        var purchasedGames = gameClient.purchaseGames(request.games(),token);

        for (PurchaseResponse purchaseResponse : purchasedGames) {
             amount = amount + purchaseResponse.price();
             logger.info("Purchased total amount {}", amount);
             logger.info("Purchased game price {}", purchaseResponse.price());
        }

        var order = this.repository.save(mapper.toOrder(request,amount));

        for (PurchaseRequest purchaseRequest : request.games()) {
            orderLineService.saveOrderLine(
                    new OrderLineRequestWithoutId(
                            order.getId(),
                            purchaseRequest.gameId()
                    )
            );
        }

        var paymentRequest = new PaymentRequest(
                order.getTotalAmount(),
                request.paymentMethod(),
                order.getId(),
                order.getReference(),
                user
        );

        PurchaseLibrary purchaseLibrary = new PurchaseLibrary(purchasedGames,username);

        paymentClient.requestOrderPayment(paymentRequest,token);
        libraryClient.purchaseLibrary(purchaseLibrary,token);
        return new ResponseOrder(String.format("Order created with ID: %d", order.getId()));
    }

    public List<OrderApp> findAllOrders() {
        return this.repository.findAll();
    }

    public List<OrderApp> findByUsername(String username) {
        return this.repository.findByUsername(username);
    }

    public OrderApp findById(Integer id) {
        return this.repository.findById(id)
                .orElseThrow(() -> new EntityNotFoundException(String.format("No order found with the provided ID: %d", id)));
    }

}
