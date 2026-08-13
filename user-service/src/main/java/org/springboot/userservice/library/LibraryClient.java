package org.springboot.userservice.library;

import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.*;

@FeignClient(
        name = "library-service",
        url = "${application.config.library-url:http://localhost:8222/api/v1/library}"
)
public interface LibraryClient {
    @PostMapping
    void createLibrary(@RequestBody LibraryRequest requestBody, @RequestHeader("Authorization") String token);

    @DeleteMapping("{username}")
    void deleteLibrary(@PathVariable("username") String username, @RequestHeader("Authorization") String token);

}
