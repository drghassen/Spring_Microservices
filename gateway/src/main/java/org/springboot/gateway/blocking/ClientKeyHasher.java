package org.springboot.gateway.blocking;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

public final class ClientKeyHasher {

    private ClientKeyHasher() {
    }

    public static String hash(String clientKey) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(clientKey.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is required by the Java platform", exception);
        }
    }
}
