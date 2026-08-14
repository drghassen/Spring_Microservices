package org.springboot.userservice.controller;

import lombok.RequiredArgsConstructor;
import org.springboot.userservice.services.UserService;
import org.springboot.userservice.user.UserResponse;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/v1/user/admin")
@PreAuthorize("hasAuthority('ADMIN')")
public class UserAdminController {
    private final UserService userService;

    // check if user exists
    @GetMapping("/exists/{user-id}")
    public ResponseEntity<Boolean> existsById(
            @PathVariable("user-id") String userId
    ) {
        return ResponseEntity.ok(userService.existsById(userId));
    }

    //get all users
    @GetMapping
    public ResponseEntity<List<UserResponse>> findAll(){
        return ResponseEntity.ok(userService.findAllUsers()
                .stream()
                .map(UserResponse::from)
                .toList());
    }

    //get Users with pagination

    @GetMapping("/pagination")
    public ResponseEntity<Page<UserResponse>> findAllByNameContaining(
          @RequestParam(required = false) String name,
          @RequestParam(defaultValue = "0") int page,
          @RequestParam(defaultValue = "10") int size
    ){
        Pageable pageable= PageRequest.of(page,size);
        return ResponseEntity.ok(userService.getUsersPagination(name, pageable)
                .map(UserResponse::from));
    }


}
