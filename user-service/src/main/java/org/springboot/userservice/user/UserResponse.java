package org.springboot.userservice.user;

/**
 * Public API representation of a user. Authentication credentials are never
 * serialized in HTTP responses.
 */
public record UserResponse(
        String id,
        String name,
        String username,
        String email,
        String address,
        Role role,
        String image
) {

    public static UserResponse from(UserApp user) {
        return new UserResponse(
                user.getId(),
                user.getName(),
                user.getUsername(),
                user.getEmail(),
                user.getAddress(),
                user.getRole(),
                user.getImage()
        );
    }
}
