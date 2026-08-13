package org.springboot.gamesservice.games;

public record GamesRequest (
         Integer id,
         String name,
         String description,
         double avaiblity,
         double price,
         Integer categoryId
){
}
