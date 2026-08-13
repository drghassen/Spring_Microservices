package org.springboot.userservice.services;

import lombok.RequiredArgsConstructor;
import org.apache.commons.lang3.StringUtils;
import org.springboot.userservice.exception.UserNotFoundException;
import org.springboot.userservice.library.LibraryClient;
import org.springboot.userservice.library.LibraryRequest;
import org.springboot.userservice.mapper.UserMapper;
import org.springboot.userservice.repository.UserRepo;
import org.springboot.userservice.request.UserRequest;
import org.springboot.userservice.user.LoginRequest;
import org.springboot.userservice.user.ResponseMapper;
import org.springboot.userservice.user.UserApp;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepo userRepo;
    private final UserMapper mapper;
    private final JwtService jwtService;
    private final AuthenticationManager authenticationManager;
    private final PasswordEncoder passwordEncoder;
    private final LibraryClient libraryClient;

    // =========================
    // IMAGES
    // =========================

    private String giveMeNewName(String oldName) {

        if (StringUtils.isBlank(oldName)) {
            throw new IllegalArgumentException(
                    "The original filename cannot be null or empty"
            );
        }

        int lastDot = oldName.lastIndexOf(".");

        if (lastDot <= 0 || lastDot == oldName.length() - 1) {
            throw new IllegalArgumentException(
                    "The file must have a valid extension"
            );
        }

        String extension = oldName
                .substring(lastDot)
                .toLowerCase();

        return UUID.randomUUID() + extension;
    }

    @Value("${uploads.dir}")
    private String uploadDir;

    public String saveImage2(MultipartFile mf) throws IOException {

        if (mf == null || mf.isEmpty()) {
            throw new IllegalArgumentException(
                    "The uploaded file cannot be null or empty"
            );
        }

        String originalFilename = mf.getOriginalFilename();

        if (StringUtils.isBlank(originalFilename)) {
            throw new IllegalArgumentException(
                    "The original filename cannot be null or empty"
            );
        }

        String newName = giveMeNewName(originalFilename);

        Path uploadPath = Paths.get(uploadDir)
                .toAbsolutePath()
                .normalize();

        Files.createDirectories(uploadPath);

        Path pathFile = uploadPath
                .resolve(newName)
                .normalize();

        if (!pathFile.startsWith(uploadPath)) {
            throw new IllegalArgumentException(
                    "Invalid file path"
            );
        }

        Files.write(pathFile, mf.getBytes());

        return newName;
    }

    // =========================
    // GET IMAGE
    // =========================

    public Resource getImageByUserId(String username) throws IOException {

        UserApp user = userRepo.findByUsername(username)
                .orElseThrow(() ->
                        new UserNotFoundException(
                                "User not found with username: " + username
                        )
                );

        String imageName = user.getImage();

        if (StringUtils.isBlank(imageName)) {
            throw new UserNotFoundException(
                    "No image found for user: " + username
            );
        }

        Path uploadPath = Paths.get(uploadDir)
                .toAbsolutePath()
                .normalize();

        Path imagePath = uploadPath
                .resolve(imageName)
                .normalize();

        if (!imagePath.startsWith(uploadPath)) {
            throw new IllegalArgumentException(
                    "Invalid image path"
            );
        }

        if (!Files.exists(imagePath) || !Files.isRegularFile(imagePath)) {
            throw new UserNotFoundException(
                    "Image not found for user: " + username
            );
        }

        return new FileSystemResource(imagePath);
    }

    // =========================
    // LOGIN
    // =========================

    public ResponseMapper login(LoginRequest request) {

        authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(
                        request.username(),
                        request.password()
                )
        );

        var user = userRepo.findByUsername(request.username())
                .orElseThrow(() ->
                        new UserNotFoundException(
                                "User not found with username: "
                                        + request.username()
                        )
                );

        var token = jwtService.generateToken(user);

        return new ResponseMapper(token);
    }

    // =========================
    // PAGINATION
    // =========================

    public Page<UserApp> getUsersPagination(
            String name,
            Pageable pageable
    ) {

        if (name == null) {
            return userRepo.findAll(pageable);
        }

        return userRepo.findByNameContaining(name, pageable);
    }

    // =========================
    // CREATE USER
    // =========================

    public ResponseMapper createUser(
            UserRequest userRequest,
            MultipartFile mf
    ) throws IOException {

        UserApp userToSave = mapper.toUser(userRequest);

        if (mf != null && !mf.isEmpty()) {
            userToSave.setImage(saveImage2(mf));
        }

        userRepo.save(userToSave);

        var token = jwtService.generateToken(userToSave);

        libraryClient.createLibrary(
                new LibraryRequest(userToSave.getId(), userToSave.getEmail(), userToSave.getUsername()),
                token
        );

        return new ResponseMapper(token);
    }

    // =========================
    // CURRENT USER
    // =========================

    public String userConnected() {

        Authentication authentication =
                SecurityContextHolder
                        .getContext()
                        .getAuthentication();

        if (authentication != null && authentication.isAuthenticated()) {

            UserApp user = (UserApp) authentication.getPrincipal();

            return user.getId();
        }

        return null;
    }

    // =========================
    // UPDATE USER BY USERNAME
    // =========================

    public ResponseMapper updateUserByUsername(
            UserRequest userRequest,
            String username
    ) {

        UserApp userToUpdate = userRepo
                .findByUsername(username)
                .orElseThrow(() ->
                        new UserNotFoundException(
                                "User with username not found: " + username
                        )
                );

        mergeUser(userToUpdate, userRequest);

        userRepo.save(userToUpdate);

        return new ResponseMapper(userToUpdate.getId());
    }

    // =========================
    // UPDATE USER
    // =========================

    public String updateUser(
            UserRequest userRequest,
            String id
    ) {

        UserApp userToUpdate = userRepo
                .findById(id)
                .orElseThrow(() ->
                        new UserNotFoundException(
                                "User with id not found: " + id
                        )
                );

        mergeUser(userToUpdate, userRequest);

        userRepo.save(userToUpdate);

        return userToUpdate.getId();
    }

    // =========================
    // FIND ALL USERS
    // =========================

    public List<UserApp> findAllUsers() {
        return userRepo.findAll();
    }

    // =========================
    // MERGE USER
    // =========================

    private void mergeUser(
            UserApp userToUpdate,
            UserRequest userRequest
    ) {

        if (StringUtils.isNotBlank(userRequest.password())) {
            userToUpdate.setPassword(
                    passwordEncoder.encode(userRequest.password())
            );
        }

        if (StringUtils.isNotBlank(userRequest.name())) {
            userToUpdate.setName(userRequest.name());
        }

        if (StringUtils.isNotBlank(userRequest.email())) {
            userToUpdate.setEmail(userRequest.email());
        }

        if (StringUtils.isNotBlank(userRequest.username())) {
            userToUpdate.setUsername(userRequest.username());
        }

        if (StringUtils.isNotBlank(userRequest.address())) {
            userToUpdate.setAddress(userRequest.address());
        }
    }

    // =========================
    // FIND BY ID
    // =========================

    public UserApp findById(String id) {

        return userRepo.findById(id)
                .orElseThrow(() ->
                        new UserNotFoundException(
                                String.format(
                                        "No User found with the provided ID: %s",
                                        id
                                )
                        )
                );
    }

    // =========================
    // FIND BY USERNAME
    // =========================

    public UserApp findByUsername(String username) {

        return userRepo.findByUsername(username)
                .orElseThrow(() ->
                        new UserNotFoundException(
                                String.format(
                                        "No User found with the provided USERNAME: %s",
                                        username
                                )
                        )
                );
    }

    // =========================
    // EXISTS
    // =========================

    public boolean existsById(String id) {
        return userRepo.findById(id).isPresent();
    }

    // =========================
    // DELETE USER
    // =========================

    public String deleteUser(
            String id,
            String token
    ) {

        var userToDelete = userRepo.findById(id)
                .orElseThrow(() ->
                        new UserNotFoundException(
                                "User not found with ID: " + id
                        )
                );

        libraryClient.deleteLibrary(
                userToDelete.getUsername(),
                token
        );

        userRepo.deleteById(id);

        return "Deleted user with id: " + id;
    }
}
