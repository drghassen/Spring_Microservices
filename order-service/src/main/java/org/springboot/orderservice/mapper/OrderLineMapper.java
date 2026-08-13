package org.springboot.orderservice.mapper;

import org.springboot.orderservice.order.OrderApp;
import org.springboot.orderservice.orderline.OrderLine;
import org.springboot.orderservice.orderline.OrderLineRequestWithoutId;
import org.springframework.stereotype.Service;

@Service
public class OrderLineMapper {
    public OrderLine toOrderLine(OrderLineRequestWithoutId request) {
        return OrderLine.builder()
                .gameId(request.gameId())
                .order(
                        OrderApp.builder()
                                .id(request.orderId())
                                .build()
                )
                .build();
    }

}
