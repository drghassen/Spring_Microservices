package org.springboot.userservice.controller;


import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springboot.userservice.request.UserRequest;
import org.springboot.userservice.services.UserService;
import org.springboot.userservice.user.ResponseMapper;
import org.springboot.userservice.user.UserResponse;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import org.springframework.core.io.Resource;

import java.io.IOException;
import java.nio.file.Files;

@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    //route for update user
    @PreAuthorize("hasAuthority('ADMIN')")
    @PutMapping("/update/{user-id}")
    public ResponseEntity<String> updateUser (
           @PathVariable("user-id") String id, @RequestBody @Valid UserRequest request
    ){
       return ResponseEntity.ok(userService.updateUser(request, id));
    }

    //route for update user
    @PreAuthorize("#username == authentication.name or hasAuthority('ADMIN')")
    @PutMapping("/update/username/{username}")
    public ResponseEntity<ResponseMapper> updateUserByUsername (
            @PathVariable("username") String username, @RequestBody @Valid UserRequest request

    ){
        return ResponseEntity.ok(userService.updateUserByUsername(request, username));
    }

    //delete user
    @PreAuthorize("hasAuthority('ADMIN')")
    @DeleteMapping("/{user-id}")
    public ResponseEntity<String> delete(
            @PathVariable("user-id") String userId,
            @RequestHeader("Authorization") String token
    ) {
        return ResponseEntity.ok(userService.deleteUser(userId,token));
    }


    // get image
    @PreAuthorize("#username == authentication.name or hasAuthority('ADMIN')")
    @GetMapping("/{username}/image")
    public ResponseEntity<Resource> getUserImage(@PathVariable String username) throws IOException {
        Resource image = userService.getImageByUserId(username);
        // Set the appropriate content type based on the file extension
        String contentType = Files.probeContentType(image.getFile().toPath());

        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(contentType))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + image.getFilename() + "\"")
                .body(image);
    }

    //get user by id
    @PreAuthorize("hasAuthority('ADMIN')")
    @GetMapping("/{user-id}")
    public ResponseEntity<UserResponse> findById(
            @PathVariable("user-id") String userId

    ) {
        return ResponseEntity.ok(UserResponse.from(userService.findById(userId)));
    }

    //get user by username
    @PreAuthorize("#username == authentication.name or hasAuthority('ADMIN')")
    @GetMapping("/username/{username}")
    public ResponseEntity<UserResponse> findByUsername(
            @PathVariable("username") String username

    ) {
        return ResponseEntity.ok(UserResponse.from(userService.findByUsername(username)));
    }

}
