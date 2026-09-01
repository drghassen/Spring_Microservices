package org.springboot.gateway.blocking;

public record AbuseDecision(Type type, int abusiveWindowCount, long windowId) {

    public static AbuseDecision none(long windowId) {
        return new AbuseDecision(Type.NONE, 0, windowId);
    }

    public enum Type {
        NONE,
        ABUSIVE_WINDOW,
        WOULD_BLOCK,
        BLOCK_CREATED,
        BLOCK_ALREADY_ACTIVE,
        REDIS_FAILURE
    }
}
