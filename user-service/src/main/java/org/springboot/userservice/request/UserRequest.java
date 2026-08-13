package org.springboot.userservice.request;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotNull;


//this record represents user Body and validation for conditions
public record UserRequest (
         String id,
         @NotNull(message = "User name is required")
         String name,
         @NotNull(message = "User email is required")
                 @Email(message = "User email is not a valid address")
         String email,
         String username,
         String password,
         String address
) {
}
