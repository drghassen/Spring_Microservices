package org.springboot.userservice.library;

/**
 * DTO used when creating a library entry for a newly registered user.
 * Contains only the fields required by the library-service (id, email, username).
 * Replaces the persistent UserApp entity on the Feign client boundary (SonarQube S4684).
 */
public record LibraryRequest(
        String id,
        String email,
        String username
) {}
