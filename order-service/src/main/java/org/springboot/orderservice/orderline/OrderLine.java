package org.springboot.orderservice.orderline;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import lombok.*;
import org.springboot.orderservice.order.OrderApp;

@AllArgsConstructor
@NoArgsConstructor
@Builder
@Setter
@Getter
@Entity

public class OrderLine {

    @Id
    @GeneratedValue
    private Integer id;
    @JsonIgnore
    @ManyToOne
    @JoinColumn(name = "order_id")
    private OrderApp order;
    private Integer gameId;
}
