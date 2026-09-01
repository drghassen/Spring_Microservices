package org.springboot.gateway.blocking;

public final class IpBlockingExchangeAttributes {

    public static final String SAFE_CLIENT_KEY =
            IpBlockingExchangeAttributes.class.getName() + ".safeClientKey";
    public static final String RATE_LIMIT_PASSED =
            IpBlockingExchangeAttributes.class.getName() + ".rateLimitPassed";
    public static final String RATE_LIMIT_REJECTED =
            IpBlockingExchangeAttributes.class.getName() + ".rateLimitRejected";
    public static final String TEMP_BLOCK_REJECTED =
            IpBlockingExchangeAttributes.class.getName() + ".temporaryBlockRejected";

    private IpBlockingExchangeAttributes() {
    }
}
