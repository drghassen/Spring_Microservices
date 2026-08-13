package org.springboot.gamesservice.controller;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springboot.gamesservice.games.GamesRequest;
import org.springboot.gamesservice.services.GamesService;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AdminGameControllerTests {

    @Mock
    private GamesService service;

    @Mock
    private MultipartFile file;

    @Test
    void createGameShouldReturnCreatedGameId() throws IOException {
        var request = new GamesRequest(null, "Game", "Description", 10.0, 29.99, 1);
        var controller = new AdminGameController(service);

        when(service.createGame(request, file)).thenReturn(42);

        var response = controller.createGame(request, file);

        assertThat(response.getBody()).isEqualTo(42);
    }

    @Test
    void updateAndDeleteShouldReturnServiceResult() {
        var request = new GamesRequest(null, "Game", "Description", 10.0, 29.99, 1);
        var controller = new AdminGameController(service);

        when(service.updateGame(request, 42)).thenReturn(42);
        when(service.deleteGame(42)).thenReturn(42);

        assertThat(controller.updateGame(42, request).getBody()).isEqualTo(42);
        assertThat(controller.deleteGame(42).getBody()).isEqualTo(42);
    }
}
