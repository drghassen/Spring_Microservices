package org.springboot.gamesservice.services;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springboot.gamesservice.exception.GamesPurchaseException;
import org.springboot.gamesservice.category.CategoryApp;
import org.springboot.gamesservice.games.GamePurchaseRequest;
import org.springboot.gamesservice.games.GamePurchaseResponse;
import org.springboot.gamesservice.games.GamesApp;
import org.springboot.gamesservice.games.GamesRequest;
import org.springboot.gamesservice.mapper.GameMapper;
import org.springboot.gamesservice.repository.CategoryRepo;
import org.springboot.gamesservice.repository.GameRepo;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.core.io.Resource;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class GamesServiceTests {

    @Mock
    private GameRepo repository;

    @Mock
    private CategoryRepo categoryRepository;

    @Mock
    private GameMapper mapper;

    @InjectMocks
    private GamesService gamesService;

    @TempDir
    Path tempDir;

    @Test
    void createGameShouldPersistMappedGameAndStoreImage() throws Exception {
        ReflectionTestUtils.setField(gamesService, "uploadDir", tempDir.toString());

        var request = new GamesRequest(1, "Game", "Description", 5.0, 29.99, 7);
        var mappedGame = GamesApp.builder().name("Game").build();
        var savedGame = GamesApp.builder().id(42).build();
        var category = CategoryApp.builder().id(7).name("Action").build();
        var file = new MockMultipartFile("file", "cover.PNG", "image/png", new ByteArrayInputStream(new byte[]{1, 2, 3}));

        when(categoryRepository.findById(7)).thenReturn(Optional.of(category));
        when(mapper.toGame(request)).thenReturn(mappedGame);
        when(repository.save(any(GamesApp.class))).thenReturn(savedGame);

        Integer result = gamesService.createGame(request, file);

        assertThat(result).isEqualTo(42);
        verify(repository).save(any(GamesApp.class));
        assertThat(mappedGame.getCategory()).isSameAs(category);
        assertThat(mappedGame.getImage()).endsWith(".png");
        try (var files = Files.list(tempDir)) {
            assertThat(files.count()).isEqualTo(1);
        }
    }

    @Test
    void createGameShouldFailWhenCategoryDoesNotExist() {
        var request = new GamesRequest(1, "Game", "Description", 5.0, 29.99, 7);
        var file = new MockMultipartFile("file", "cover.PNG", "image/png", new byte[]{1, 2, 3});

        when(categoryRepository.findById(7)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> gamesService.createGame(request, file))
                .isInstanceOf(EntityNotFoundException.class)
                .hasMessageContaining("Category not found");

        verify(repository, never()).save(any(GamesApp.class));
    }

    @Test
    void updateGameShouldMergeOnlyProvidedFields() {
        var existingGame = GamesApp.builder()
                .id(10)
                .name("Old")
                .description("Old desc")
                .price(12.5)
                .avaiblity(4)
                .build();
        var request = new GamesRequest(null, "New", null, 0.0, 19.99, 8);
        var category = CategoryApp.builder().id(8).name("RPG").build();

        when(repository.findById(10)).thenReturn(Optional.of(existingGame));
        when(categoryRepository.findById(8)).thenReturn(Optional.of(category));
        when(repository.save(existingGame)).thenReturn(existingGame);

        Integer result = gamesService.updateGame(request, 10);

        assertThat(result).isEqualTo(10);
        assertThat(existingGame.getName()).isEqualTo("New");
        assertThat(existingGame.getDescription()).isEqualTo("Old desc");
        assertThat(existingGame.getPrice()).isEqualTo(19.99);
        assertThat(existingGame.getAvaiblity()).isEqualTo(4);
        assertThat(existingGame.getCategory()).isSameAs(category);
        verify(repository).save(existingGame);
    }

    @Test
    void purchaseGamesShouldDecreaseStockAndReturnResponses() {
        var requests = List.of(new GamePurchaseRequest(2), new GamePurchaseRequest(1));
        var gameOne = GamesApp.builder().id(1).name("One").description("D1").price(10).avaiblity(3).build();
        var gameTwo = GamesApp.builder().id(2).name("Two").description("D2").price(15).avaiblity(2).build();

        when(repository.findAllByIdInOrderById(List.of(2, 1))).thenReturn(List.of(gameOne, gameTwo));
        when(repository.save(any(GamesApp.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(mapper.toGamePurchaseResponse(gameOne)).thenReturn(new GamePurchaseResponse(1, "One", "D1", 10));
        when(mapper.toGamePurchaseResponse(gameTwo)).thenReturn(new GamePurchaseResponse(2, "Two", "D2", 15));

        var responses = gamesService.purchaseGames(requests);

        assertThat(responses).hasSize(2);
        assertThat(gameOne.getAvaiblity()).isEqualTo(2);
        assertThat(gameTwo.getAvaiblity()).isEqualTo(1);
        verify(repository).save(gameOne);
        verify(repository).save(gameTwo);
    }

    @Test
    void purchaseGamesShouldFailWhenStockIsInsufficient() {
        var requests = List.of(new GamePurchaseRequest(1));
        var game = GamesApp.builder().id(1).name("One").description("D1").price(10).avaiblity(0).build();

        when(repository.findAllByIdInOrderById(List.of(1))).thenReturn(List.of(game));

        assertThatThrownBy(() -> gamesService.purchaseGames(requests))
                .isInstanceOf(GamesPurchaseException.class)
                .hasMessageContaining("Insufficient stock quantity");

        verify(repository, never()).save(any(GamesApp.class));
    }

    @Test
    void getGameImageShouldReturnFileResource() throws IOException {
        ReflectionTestUtils.setField(gamesService, "uploadDir", tempDir.toString());

        var imageFile = tempDir.resolve("cover.png");
        Files.writeString(imageFile, "image-content");
        var game = GamesApp.builder().id(5).image("cover.png").build();

        when(repository.findById(5)).thenReturn(Optional.of(game));

        Resource resource = gamesService.getGameImage(5);

        assertThat(resource.exists()).isTrue();
        assertThat(resource.getFilename()).isEqualTo("cover.png");
    }

    @Test
    void repositoryOperationsShouldDelegateToRepository() {
        var pageable = PageRequest.of(0, 5);
        var game = GamesApp.builder().id(5).name("Game").build();
        var page = new PageImpl<>(List.of(game));

        when(repository.findByNameContaining("Game", pageable)).thenReturn(page);
        when(repository.findById(5)).thenReturn(Optional.of(game));
        when(repository.findAll()).thenReturn(List.of(game));

        assertThat(gamesService.getGamesPagination("Game", pageable)).isSameAs(page);
        assertThat(gamesService.findById(5)).isSameAs(game);
        assertThat(gamesService.findAll()).containsExactly(game);
        assertThat(gamesService.deleteGame(5)).isEqualTo(5);

        verify(repository).deleteById(5);
    }
}
