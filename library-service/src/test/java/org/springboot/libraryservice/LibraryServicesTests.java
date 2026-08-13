package org.springboot.libraryservice;


import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springboot.libraryservice.games.Games;
import org.springboot.libraryservice.library.LibraryApp;
import org.springboot.libraryservice.purchase.PurchaseRequest;
import org.springboot.libraryservice.repository.LibraryRepo;
import org.springboot.libraryservice.service.LibraryService;
import org.springboot.libraryservice.user.UserApp;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.ArrayList;
import java.util.List;

import static com.mongodb.assertions.Assertions.*;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@WebMvcTest
@AutoConfigureMockMvc(addFilters = false)
@ExtendWith(MockitoExtension.class)
class LibraryServicesTests {

    private static final String BASE_URL = "/api/v1/library";
    private static final String AUTH_HEADER = "Authorization";
    private static final String TOKEN = "DAMPPY_TOKEN";
    private LibraryApp libraryApp;
    private Games game1;
    private Games game2;
    private Games game3;
    private Games game4;
    private PurchaseRequest purchaseRequest;
    private UserApp userApp;
    private UserApp userAppForCreation;
    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private LibraryService libraryService;

    @Mock
    private LibraryRepo libraryRepo;  // Mocking the repository

    private LibraryApp libraryAppWrong;


    @BeforeEach
    void setUp() {
        // Initialize objects
        libraryApp = new LibraryApp("testusertest","userTest",null);
        userApp = new UserApp(null, "userTest@userTest.com", "userTest");
        game1 = new Games(1, "LOL", "hello world", 55.2);
        game2 = new Games(2, "CS2", "hello world", 50.0);
        game3 = new Games(3, "VALORANT", "hello world", 30.0);
        game4 = new Games(4, "FIFA25", "hello world", 40.0);
        purchaseRequest = new PurchaseRequest(List.of(game1, game2, game3, game4), userApp.username());
        libraryAppWrong = new LibraryApp("lib","user",null);
        userAppForCreation=new UserApp("user","user@user.com","user2");
        libraryService.createLibrary(userApp);
    }

    @Test
    void testDeleteLibraryReturnValue() {
        when(libraryService.deleteLibrary(userApp.username())).thenReturn("ID");
        String result = libraryService.deleteLibrary(userApp.username());
        assertThat(result).isNotNull().isEqualTo("ID");
    }

    @Test
    void testDeleteLibraryReturnWrongValue() {
        when(libraryService.deleteLibrary(userApp.username())).thenReturn("ID");
        String result = libraryService.deleteLibrary(userApp.username());
        assertThat(result).isNotNull();
        assertFalse(result.equals(libraryAppWrong.getId()));
    }

    @Test
    void testGetLibraryReturnValue() {
        when(libraryService.getLibrary(userApp.username())).thenReturn(libraryApp);
        LibraryApp result = libraryService.getLibrary(userApp.username());
        assertTrue(result.equals(libraryApp));
    }

    @Test
    void testGetLibraryReturnWrongValue(){
        when(libraryService.getLibrary(userApp.username())).thenReturn(libraryApp);
        LibraryApp result = libraryService.getLibrary(userApp.username());
        assertFalse(result.equals(libraryAppWrong));
    }

    @Test
    void testUpdateLibraryReturnValue() {
        libraryService.updateLibrary(purchaseRequest);
        verify(libraryService).updateLibrary(purchaseRequest);
    }


}
