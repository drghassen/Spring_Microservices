package org.springboot.gamesservice.services;


import jakarta.persistence.EntityNotFoundException;
import lombok.RequiredArgsConstructor;
import org.apache.commons.lang3.StringUtils;
import org.springboot.gamesservice.category.CategoryApp;
import org.springboot.gamesservice.exception.GamesPurchaseException;
import org.springboot.gamesservice.games.*;
import org.springboot.gamesservice.mapper.GameMapper;
import org.springboot.gamesservice.repository.CategoryRepo;
import org.springboot.gamesservice.repository.GameRepo;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class GamesService {
    private final GameRepo repository;
    private final CategoryRepo categoryRepository;
    private final GameMapper mapper;


    //find all by pagination
    public Page<GamesApp> getGamesPagination(
            String name,
            Pageable pageable
    ){
        return repository.findByNameContaining(name,pageable);
    }

    //IMAGEEEE

    // GET IMAGES :
    public Resource getGameImage(Integer gameId) throws IOException {

        GamesApp game = repository.findById(gameId)
                .orElseThrow(() ->
                        new EntityNotFoundException(
                                "Game not found with ID: " + gameId
                        )
                );

        String imageName = game.getImage();

        if (StringUtils.isBlank(imageName)) {
            throw new EntityNotFoundException(
                    "No image found for game ID: " + gameId
            );
        }

        Path uploadPath = Paths.get(uploadDir);

        Path imagePath = uploadPath
                .resolve(imageName)
                .normalize();

        if (!imagePath.startsWith(uploadPath.normalize())) {
            throw new IllegalArgumentException(
                    "Invalid image path"
            );
        }

        if (!Files.exists(imagePath) || !Files.isRegularFile(imagePath)) {
            throw new EntityNotFoundException(
                    "Image not found for game ID: " + gameId
            );
        }

        return new FileSystemResource(imagePath);
    }
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

        String extension = oldName.substring(lastDot).toLowerCase();

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

        Path uploadPath = Paths.get(uploadDir).toAbsolutePath().normalize();

        Files.createDirectories(uploadPath);

        Path pathFile = uploadPath.resolve(newName).normalize();

        if (!pathFile.startsWith(uploadPath)) {
            throw new IllegalArgumentException("Invalid file path");
        }

        Files.copy(mf.getInputStream(), pathFile);

        return newName;
    }

    //creates a game and convert from game request to gameapp then save it to BDD
    public Integer createGame(
            GamesRequest request,
            MultipartFile mf
    ) throws IOException {
        if (request.categoryId() == null) {
            throw new IllegalArgumentException("Category is required");
        }

        var category = categoryRepository.findById(request.categoryId())
                .orElseThrow(() -> new EntityNotFoundException(
                        "Category not found with ID: " + request.categoryId()
                ));

        var game = mapper.toGame(request);
        game.setCategory(category);

        if (mf != null && !mf.isEmpty()){
            game.setImage(saveImage2(mf));
        }
        return repository.save(game).getId();
    }

    //update Game
    public Integer updateGame(
            GamesRequest request,
            Integer gameId
    ){
        var gameToUpdate = repository.findById(gameId).orElseThrow(EntityNotFoundException::new);
        mergeGame(gameToUpdate,request);
        repository.save(gameToUpdate);
        return gameToUpdate.getId();
    }

    private void mergeGame(GamesApp game, GamesRequest gamesRequest) {
        if (StringUtils.isNotBlank(gamesRequest.name())){
            game.setName(gamesRequest.name());
        }
        if (StringUtils.isNotBlank(gamesRequest.description())){
            game.setDescription(gamesRequest.description());
        }
        if (gamesRequest.price()!=0.0){
            game.setPrice(gamesRequest.price());
        }
        if (gamesRequest.avaiblity()!=0.0){
            game.setAvaiblity(gamesRequest.avaiblity());
        }
        if (gamesRequest.categoryId()!=null){
            CategoryApp category = categoryRepository.findById(gamesRequest.categoryId())
                    .orElseThrow(() -> new EntityNotFoundException(
                            "Category not found with ID: " + gamesRequest.categoryId()
                    ));
            game.setCategory(category);
        }
    }

    //delete Game
    public Integer deleteGame(Integer gameId) {
        repository.deleteById(gameId);
        return gameId;
    }

    //return a game by id and convert from gameapp to gameResponse if there is no game with that it, it throw excp
    public GamesApp findById(Integer id) {
        return repository.findById(id)

                .orElseThrow(() -> new EntityNotFoundException("Game not found with ID:: " + id));
    }

    //return all games and convert from gameApp to game response
    public List<GamesApp> findAll() {
        return repository.findAll();
    }


    @Transactional(rollbackFor = GamesPurchaseException.class)
    public List<GamePurchaseResponse> purchaseGames(
            List<GamePurchaseRequest> request
    ) {
        //get gamesIds that will be purchased (gameIds is a list)
        var gameIds = request
                .stream()
                .map(GamePurchaseRequest::gameId)
                .toList();
        //get Games from BDD with redifined method in gamerepo
        var storedGames = repository.findAllByIdInOrderById(gameIds);
        // if gameIds != storedGames (fetched from BDD) that means there is a game or more that not exist in BDD
        if (gameIds.size() != storedGames.size()) {
            throw new GamesPurchaseException("One or more games does not exist");
        }

        //sorting gameids from request
        var sortedRequest = request
                .stream()
                .sorted(Comparator.comparing(GamePurchaseRequest::gameId))
                .toList();

        var purchasedGames = new ArrayList<GamePurchaseResponse>();
        for (int i = 0; i < storedGames.size(); i++) {
            var game = storedGames.get(i);
            var gameRequest = sortedRequest.get(i);
            if (game.getAvaiblity() < 1) {
                throw new GamesPurchaseException("Insufficient stock quantity for game with ID:: " + gameRequest.gameId());
            }
            var newAvailableQuantity = game.getAvaiblity() - 1;
            game.setAvaiblity(newAvailableQuantity);
            repository.save(game);
            purchasedGames.add(mapper.toGamePurchaseResponse(game));
        }
        return purchasedGames;
    }


}
