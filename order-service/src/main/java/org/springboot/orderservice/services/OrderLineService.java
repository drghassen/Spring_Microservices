package org.springboot.orderservice.services;
import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import org.springboot.orderservice.mapper.OrderLineMapper;
import org.springboot.orderservice.orderline.OrderLine;
import org.springboot.orderservice.orderline.OrderLineRequestWithoutId;
import org.springboot.orderservice.repository.OrderLineRepository;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
public class OrderLineService {

    private final OrderLineRepository repository;
    private final OrderLineMapper mapper;

    @Transactional
    public Integer saveOrderLine(OrderLineRequestWithoutId request) {
        var orderLine = mapper.toOrderLine(request);
        var orderLineId= repository.save(orderLine).getId();
        repository.flush();
        return orderLineId;
    }


    public List<OrderLine> findAllByOrderId(Integer orderId) {
        return repository.findAllByOrderId(orderId);
    }
}
