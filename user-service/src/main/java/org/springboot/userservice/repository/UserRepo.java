package org.springboot.userservice.repository;

import org.springboot.userservice.user.UserApp;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface UserRepo extends MongoRepository<UserApp, String> {
    Optional<UserApp> findByUsername(String username);

    @Query(" { 'name': { $regex: '^?0', $options: 'i' } }")
    Page<UserApp> findByNameContaining(@Param("name") String name, Pageable pageable);

    @Override
    Page<UserApp> findAll(Pageable pageable);

}
