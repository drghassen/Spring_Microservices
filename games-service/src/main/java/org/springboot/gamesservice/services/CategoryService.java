package org.springboot.gamesservice.services;


import jakarta.persistence.EntityNotFoundException;
import lombok.AllArgsConstructor;
import org.apache.commons.lang3.StringUtils;
import org.springboot.gamesservice.category.CategoryApp;
import org.springboot.gamesservice.category.CategoryRequest;
import org.springboot.gamesservice.mapper.CategoryMapper;
import org.springboot.gamesservice.repository.CategoryRepo;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@AllArgsConstructor
public class CategoryService {
    private final CategoryRepo repository;
    private final CategoryMapper mapper;

    public Integer createCategory(
            CategoryRequest request
    ) {
        var category = mapper.toCategory(request);
        return repository.save(category).getId();
    }

    //update Game
    public Integer updateCategory(
            CategoryRequest request,
            Integer categoryId
    ){
        var categoryToUpdate = repository.findById(categoryId).orElseThrow(EntityNotFoundException::new);
        mergeCategory(categoryToUpdate,request);
        repository.save(categoryToUpdate);
        return categoryToUpdate.getId();
    }

    private void mergeCategory(CategoryApp category, CategoryRequest categoryRequest) {
        if (StringUtils.isNotBlank(categoryRequest.name())){
            category.setName(categoryRequest.name());
        }
        if (StringUtils.isNotBlank(categoryRequest.description())){
            category.setDescription(categoryRequest.description());
        }
    }

    //delete Category
    public Integer deleteCategory(Integer categoryId) {
        CategoryApp category= repository.findById(categoryId).orElseThrow(EntityNotFoundException::new);
        repository.deleteById(categoryId);
        return category.getId();
    }

    //return a game by id and convert from categoryapp to categoryResponse if there is no category with that it, it throw excp
    public CategoryApp findById(Integer id) {
        return repository.findById(id)
                .orElseThrow(() -> new EntityNotFoundException("Category not found with ID:: " + id));
    }

    //return all games and convert from categoryapp to categoryResponse
    public List<CategoryApp> findAll() {
        return repository.findAll();
    }

}
