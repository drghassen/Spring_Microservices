package org.springboot.userservice.services;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springboot.userservice.exception.UserNotFoundException;
import org.springboot.userservice.library.LibraryClient;
import org.springboot.userservice.mapper.UserMapper;
import org.springboot.userservice.repository.UserRepo;
import org.springboot.userservice.request.UserRequest;
import org.springboot.userservice.user.LoginRequest;
import org.springboot.userservice.user.Role;
import org.springboot.userservice.user.UserApp;
import org.springframework.core.io.Resource;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
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
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UserServiceTests {

    @Mock
    private UserRepo userRepo;

    @Mock
    private UserMapper mapper;

    @Mock
    private JwtService jwtService;

    @Mock
    private AuthenticationManager authenticationManager;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private LibraryClient libraryClient;

    @InjectMocks
    private UserService userService;

    @TempDir
    Path tempDir;

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void saveImageShouldStoreFileWithNormalizedGeneratedName() throws IOException {
        ReflectionTestUtils.setField(userService, "uploadDir", tempDir.toString());
        var file = new MockMultipartFile("file", "avatar.PNG", "image/png", new ByteArrayInputStream(new byte[]{1, 2, 3}));

        String storedName = userService.saveImage2(file);

        assertThat(storedName).endsWith(".png");
        assertThat(tempDir.resolve(storedName)).exists().hasBinaryContent(new byte[]{1, 2, 3});
    }

    @Test
    void saveImageShouldRejectEmptyFileAndInvalidFilename() {
        ReflectionTestUtils.setField(userService, "uploadDir", tempDir.toString());
        var emptyFile = new MockMultipartFile("file", "avatar.png", "image/png", new byte[0]);
        var invalidName = new MockMultipartFile("file", "avatar", "image/png", new byte[]{1});

        assertThatThrownBy(() -> userService.saveImage2(emptyFile))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("uploaded file");

        assertThatThrownBy(() -> userService.saveImage2(invalidName))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("valid extension");
    }

    @Test
    void getImageByUserIdShouldReturnExistingImageResource() throws IOException {
        ReflectionTestUtils.setField(userService, "uploadDir", tempDir.toString());
        Files.writeString(tempDir.resolve("avatar.png"), "image-content");
        var user = UserApp.builder().username("jane").image("avatar.png").build();

        when(userRepo.findByUsername("jane")).thenReturn(Optional.of(user));

        Resource resource = userService.getImageByUserId("jane");

        assertThat(resource.exists()).isTrue();
        assertThat(resource.getFilename()).isEqualTo("avatar.png");
    }

    @Test
    void getImageByUserIdShouldFailWhenUserOrImageIsMissing() {
        ReflectionTestUtils.setField(userService, "uploadDir", tempDir.toString());
        var userWithoutImage = UserApp.builder().username("jane").build();

        when(userRepo.findByUsername("missing")).thenReturn(Optional.empty());
        when(userRepo.findByUsername("jane")).thenReturn(Optional.of(userWithoutImage));

        assertThatThrownBy(() -> userService.getImageByUserId("missing"))
                .isInstanceOf(UserNotFoundException.class);

        assertThatThrownBy(() -> userService.getImageByUserId("jane"))
                .isInstanceOf(UserNotFoundException.class);
    }

    @Test
    void loginShouldAuthenticateAndReturnGeneratedToken() {
        var request = new LoginRequest("jane", "secret");
        var user = UserApp.builder().username("jane").build();
        var authentication = mock(Authentication.class);

        when(authenticationManager.authenticate(any(UsernamePasswordAuthenticationToken.class))).thenReturn(authentication);
        when(userRepo.findByUsername("jane")).thenReturn(Optional.of(user));
        when(jwtService.generateToken(user)).thenReturn("jwt-token");

        var response = userService.login(request);

        assertThat(response.message()).isEqualTo("jwt-token");
        verify(authenticationManager).authenticate(any(UsernamePasswordAuthenticationToken.class));
    }

    @Test
    void getUsersPaginationShouldSearchByNameOnlyWhenNameIsProvided() {
        var pageable = PageRequest.of(0, 5);
        var allUsers = new PageImpl<>(List.of(UserApp.builder().username("all").build()));
        var filteredUsers = new PageImpl<>(List.of(UserApp.builder().username("jane").build()));

        when(userRepo.findAll(pageable)).thenReturn(allUsers);
        when(userRepo.findByNameContaining("Jane", pageable)).thenReturn(filteredUsers);

        assertThat(userService.getUsersPagination(null, pageable)).isSameAs(allUsers);
        assertThat(userService.getUsersPagination("Jane", pageable)).isSameAs(filteredUsers);
    }

    @Test
    void createUserShouldSaveUserCreateLibraryAndReturnToken() throws IOException {
        ReflectionTestUtils.setField(userService, "uploadDir", tempDir.toString());
        var request = userRequest("id-1", "Jane", "jane@example.com", "jane", "secret", "Tunis");
        var user = UserApp.builder().id("id-1").email("jane@example.com").username("jane").build();
        var file = new MockMultipartFile("file", "avatar.jpg", "image/jpeg", new byte[]{1});

        when(mapper.toUser(request)).thenReturn(user);
        when(jwtService.generateToken(user)).thenReturn("jwt-token");

        var response = userService.createUser(request, file);

        assertThat(response.message()).isEqualTo("jwt-token");
        assertThat(user.getImage()).endsWith(".jpg");
        verify(userRepo).save(user);
        verify(libraryClient).createLibrary(
                argThat(requestBody -> requestBody.id().equals("id-1")
                        && requestBody.email().equals("jane@example.com")
                        && requestBody.username().equals("jane")),
                eq("jwt-token")
        );
    }

    @Test
    void userConnectedShouldReturnAuthenticatedUserIdOrNull() {
        var authentication = mock(Authentication.class);
        var user = UserApp.builder().id("user-id").build();

        when(authentication.isAuthenticated()).thenReturn(true);
        when(authentication.getPrincipal()).thenReturn(user);
        SecurityContextHolder.getContext().setAuthentication(authentication);

        assertThat(userService.userConnected()).isEqualTo("user-id");

        SecurityContextHolder.clearContext();
        assertThat(userService.userConnected()).isNull();
    }

    @Test
    void updateUserByUsernameShouldMergeProvidedFieldsAndEncodePassword() {
        var existingUser = UserApp.builder()
                .id("id-1")
                .name("Old")
                .email("old@example.com")
                .username("old")
                .password("old-password")
                .address("Old address")
                .build();
        var request = userRequest(null, "New", "new@example.com", "new", "secret", "New address");

        when(userRepo.findByUsername("old")).thenReturn(Optional.of(existingUser));
        when(passwordEncoder.encode("secret")).thenReturn("encoded-secret");

        var response = userService.updateUserByUsername(request, "old");

        assertThat(response.message()).isEqualTo("id-1");
        assertThat(existingUser.getName()).isEqualTo("New");
        assertThat(existingUser.getEmail()).isEqualTo("new@example.com");
        assertThat(existingUser.getUsername()).isEqualTo("new");
        assertThat(existingUser.getPassword()).isEqualTo("encoded-secret");
        assertThat(existingUser.getAddress()).isEqualTo("New address");
        verify(userRepo).save(existingUser);
    }

    @Test
    void updateUserShouldKeepExistingValuesWhenRequestFieldsAreBlank() {
        var existingUser = UserApp.builder()
                .id("id-1")
                .name("Old")
                .email("old@example.com")
                .username("old")
                .password("old-password")
                .address("Old address")
                .build();
        var request = userRequest(null, " ", "", null, null, "\t");

        when(userRepo.findById("id-1")).thenReturn(Optional.of(existingUser));

        String id = userService.updateUser(request, "id-1");

        assertThat(id).isEqualTo("id-1");
        assertThat(existingUser.getName()).isEqualTo("Old");
        assertThat(existingUser.getEmail()).isEqualTo("old@example.com");
        assertThat(existingUser.getUsername()).isEqualTo("old");
        assertThat(existingUser.getPassword()).isEqualTo("old-password");
        assertThat(existingUser.getAddress()).isEqualTo("Old address");
        verify(passwordEncoder, never()).encode(any());
        verify(userRepo).save(existingUser);
    }

    @Test
    void findAndDeleteOperationsShouldUseRepositoryAndLibraryClient() {
        var user = UserApp.builder().id("id-1").username("jane").role(Role.USER).build();
        var users = List.of(user);

        when(userRepo.findAll()).thenReturn(users);
        when(userRepo.findById("id-1")).thenReturn(Optional.of(user));
        when(userRepo.findByUsername("jane")).thenReturn(Optional.of(user));

        assertThat(userService.findAllUsers()).isSameAs(users);
        assertThat(userService.findById("id-1")).isSameAs(user);
        assertThat(userService.findByUsername("jane")).isSameAs(user);
        assertThat(userService.existsById("id-1")).isTrue();
        assertThat(userService.deleteUser("id-1", "Bearer token")).isEqualTo("Deleted user with id: id-1");

        verify(libraryClient).deleteLibrary("jane", "Bearer token");
        verify(userRepo).deleteById("id-1");
    }

    @Test
    void findByIdShouldFailWhenUserDoesNotExist() {
        when(userRepo.findById("missing")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> userService.findById("missing"))
                .isInstanceOf(UserNotFoundException.class);
    }

    private UserRequest userRequest(
            String id,
            String name,
            String email,
            String username,
            String password,
            String address
    ) {
        return new UserRequest(id, name, email, username, password, address);
    }

}
