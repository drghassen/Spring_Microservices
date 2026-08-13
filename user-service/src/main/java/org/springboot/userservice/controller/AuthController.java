package org.springboot.userservice.controller;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springboot.userservice.request.UserRequest;
import org.springboot.userservice.services.UserService;
import org.springboot.userservice.user.LoginRequest;
import org.springboot.userservice.user.ResponseMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.logging.Logger;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final UserService userService;
    Logger logger = Logger.getLogger(AuthController.class.getName());
    @Value("${uploads.dir}")
    private String uploadDir;

    //route for login
    @PostMapping("/login")
    public ResponseEntity<ResponseMapper> login(
            @RequestBody LoginRequest request
    )  {

        return ResponseEntity.ok(userService.login(request));
    }

    //route for creation user
    @PostMapping(value="/register")
    public ResponseEntity<ResponseMapper> createUser (
            @ModelAttribute @Valid UserRequest request
            , @RequestParam("file") MultipartFile file
    ) throws IOException {
        logger.info(uploadDir);
        logger.info((System.getProperty("user.dir")));
        return ResponseEntity.ok(userService.createUser(request,file));
    }


}
