package org.springboot.gamesservice.controller;


import lombok.RequiredArgsConstructor;
import org.springboot.gamesservice.category.CategoryApp;
import org.springboot.gamesservice.category.CategoryRequest;
import org.springboot.gamesservice.services.CategoryService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/v1/category/admin")
public class AdminCategoryController {
    private final CategoryService service;

    //CRUD CATEGORY
    @PostMapping
    public ResponseEntity<Integer> createCategory(
            @RequestBody CategoryRequest request
    ) {
        return ResponseEntity.ok(service.createCategory(request));
    }
    @PutMapping("/{category-id}")
    public ResponseEntity<Integer> updateCategory(
            @PathVariable("category-id") Integer id, @RequestBody CategoryRequest request
    ){
        return ResponseEntity.ok(service.updateCategory(request,id));
    }

    @DeleteMapping("/{category-id}")
    public ResponseEntity<Integer> deleteCategory(
            @PathVariable("category-id") Integer id
    ){
        return ResponseEntity.ok(service.deleteCategory(id));
    }

    @GetMapping("/{category-id}")
    public ResponseEntity<CategoryApp> findById(
            @PathVariable("category-id") Integer categoryId
    ) {
        return ResponseEntity.ok(service.findById(categoryId));
    }

    @GetMapping
    public ResponseEntity<List<CategoryApp>> findAll() {
        return ResponseEntity.ok(service.findAll());
    }

}
