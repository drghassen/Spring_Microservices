package org.springboot.libraryservice;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.BDDMockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springboot.libraryservice.controller.LibraryController;
import org.springboot.libraryservice.library.LibraryApp;
import org.springboot.libraryservice.purchase.PurchaseRequest;
import org.springboot.libraryservice.service.LibraryService;
import org.springboot.libraryservice.user.UserApp;
import org.springboot.libraryservice.games.Games;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import java.util.List;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(LibraryController.class)
@AutoConfigureMockMvc(addFilters = false)
@ExtendWith(MockitoExtension.class)
class LibraryControllersTests {

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

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private LibraryService libraryService;

    @BeforeEach
    void setUp() {
        // Initialize objects
        libraryApp = new LibraryApp("libraryidtesttest", "userTest", null);
        userApp = new UserApp("usertestuser", "userTest@userTest.com", "userTest");
        game1 = new Games(1, "LOL", "hello world", 55.2);
        game2 = new Games(2, "CS2", "hello world", 50.0);
        game3 = new Games(3, "VALORANT", "hello world", 30.0);
        game4 = new Games(4, "FIFA25", "hello world", 40.0);
        purchaseRequest = new PurchaseRequest(List.of(game1, game2, game3, game4), userApp.username());
    }

    @Test
    void libraryCreation() throws Exception {
        doNothing().when(libraryService).createLibrary(any());
        ResultActions response = mockMvc.perform(post(BASE_URL)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(userApp))
                .header(AUTH_HEADER,TOKEN));
        response.andExpect(status().isOk());
    }
    @Test
    void libraryUpdate() throws Exception {
        libraryCreation();
        doNothing().when(libraryService).updateLibrary(any());
        ResultActions response = mockMvc.perform(put(BASE_URL+"/purchase")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(purchaseRequest))
        );
        response.andExpect(status().isOk());
    }
    @Test
    void libraryDelete() throws Exception {
        libraryUpdate();
        when(libraryService.deleteLibrary(any())).thenReturn("true");  // Or whatever value deleteLibrary() returns
        ResultActions response = mockMvc.perform(delete(BASE_URL+"/"+userApp.username())
        .contentType(MediaType.APPLICATION_JSON));
        response.andExpect(status().isOk());
    }

    @Test
    void libraryList() throws Exception {
        libraryUpdate();
        BDDMockito.given(libraryService.getLibrary(any())).willReturn(libraryApp);
        ResultActions response = mockMvc.perform(get(BASE_URL)
                .contentType(MediaType.APPLICATION_JSON)
                .param("username",userApp.username())
                .header(AUTH_HEADER,TOKEN));
        response.andExpect(status().isOk());
    }

}
