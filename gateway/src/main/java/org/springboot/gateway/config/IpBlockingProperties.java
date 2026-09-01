package org.springboot.gateway.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.util.Assert;

import java.time.Duration;

@ConfigurationProperties(prefix = "ip-blocking")
public class IpBlockingProperties {

    private Mode mode = Mode.SHADOW;
    private final Window window = new Window();
    private final Block block = new Block();

    public Mode getMode() {
        return mode;
    }

    public void setMode(Mode mode) {
        this.mode = mode;
    }

    public Window getWindow() {
        return window;
    }

    public Block getBlock() {
        return block;
    }

    public void validate() {
        Assert.notNull(mode, "ip-blocking.mode is required");
        Assert.isTrue(!window.duration.isNegative() && !window.duration.isZero(),
                "ip-blocking.window.duration must be positive");
        Assert.isTrue(window.rateLimit429Threshold > 0,
                "ip-blocking.window.rate-limit-429-threshold must be positive");
        Assert.isTrue(window.abusiveWindowsRequired >= 3,
                "ip-blocking.window.abusive-windows-required must be at least 3");
        Assert.isTrue(!block.duration.isNegative() && !block.duration.isZero(),
                "ip-blocking.block.duration must be positive");
    }

    public enum Mode {
        OFF,
        SHADOW,
        ENFORCE
    }

    public static class Window {
        private Duration duration = Duration.ofSeconds(10);
        private int rateLimit429Threshold = 3;
        private int abusiveWindowsRequired = 3;

        public Duration getDuration() {
            return duration;
        }

        public void setDuration(Duration duration) {
            this.duration = duration;
        }

        public int getRateLimit429Threshold() {
            return rateLimit429Threshold;
        }

        public void setRateLimit429Threshold(int rateLimit429Threshold) {
            this.rateLimit429Threshold = rateLimit429Threshold;
        }

        public int getAbusiveWindowsRequired() {
            return abusiveWindowsRequired;
        }

        public void setAbusiveWindowsRequired(int abusiveWindowsRequired) {
            this.abusiveWindowsRequired = abusiveWindowsRequired;
        }
    }

    public static class Block {
        private Duration duration = Duration.ofSeconds(60);

        public Duration getDuration() {
            return duration;
        }

        public void setDuration(Duration duration) {
            this.duration = duration;
        }
    }
}
