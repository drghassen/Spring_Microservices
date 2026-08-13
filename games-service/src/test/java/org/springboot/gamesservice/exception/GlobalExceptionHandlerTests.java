package org.springboot.gamesservice.exception;

import jakarta.persistence.EntityNotFoundException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

import static org.assertj.core.api.Assertions.assertThat;

class GlobalExceptionHandlerTests {

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @Test
    void shouldMapIllegalArgumentToBadRequestProblem() {
        var problem = handler.handleBadRequest(new IllegalArgumentException("invalid request"));

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(problem.getTitle()).isEqualTo("Bad request");
        assertThat(problem.getDetail()).isEqualTo("invalid request");
    }

    @Test
    void shouldMapEntityNotFoundToNotFoundProblem() {
        var problem = handler.handleNotFound(new EntityNotFoundException("missing game"));

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.NOT_FOUND.value());
        assertThat(problem.getTitle()).isEqualTo("Resource not found");
        assertThat(problem.getDetail()).isEqualTo("missing game");
    }

    @Test
    void shouldMapPurchaseErrorToBadRequestProblem() {
        var problem = handler.handlePurchaseError(new GamesPurchaseException("stock exhausted"));

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(problem.getTitle()).isEqualTo("Purchase rejected");
        assertThat(problem.getDetail()).isEqualTo("stock exhausted");
    }
}
