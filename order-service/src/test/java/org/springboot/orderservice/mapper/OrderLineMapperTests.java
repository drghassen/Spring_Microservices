package org.springboot.orderservice.mapper;

import org.junit.jupiter.api.Test;
import org.springboot.orderservice.orderline.OrderLineRequestWithoutId;

import static org.assertj.core.api.Assertions.assertThat;

class OrderLineMapperTests {

    private final OrderLineMapper mapper = new OrderLineMapper();

    @Test
    void toOrderLineShouldMapOrderAndGameIds() {
        var request = new OrderLineRequestWithoutId(99, 123);

        var result = mapper.toOrderLine(request);

        assertThat(result).isNotNull();
        assertThat(result.getGameId()).isEqualTo(123);
        assertThat(result.getOrder()).isNotNull();
        assertThat(result.getOrder().getId()).isEqualTo(99);
    }
}
