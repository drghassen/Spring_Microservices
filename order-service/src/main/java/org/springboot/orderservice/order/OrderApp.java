package org.springboot.orderservice.order;

import jakarta.persistence.*;
import lombok.*;
import org.springboot.orderservice.orderline.OrderLine;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.time.LocalDateTime;
import java.util.List;

@AllArgsConstructor
@NoArgsConstructor
@Builder
@Setter
@Getter
@Entity
@ToString
@EntityListeners(AuditingEntityListener.class)
@Table(name = "orders")
public class OrderApp {
    @Id
    @GeneratedValue
    private Integer id;
    private String reference;
    private double totalAmount;
    @Enumerated(EnumType.STRING)
    private PaymentMethod paymentMethod;
    private String username;
    @OneToMany(mappedBy = "order")
    private List<OrderLine> orderLines;
    @CreatedDate
    @Column(updatable = false,nullable = false)
    private LocalDateTime createdAt;
    @LastModifiedDate
    @Column(insertable = false)
    private LocalDateTime updatedAt;


}
