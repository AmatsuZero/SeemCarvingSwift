package io.github.seamcarving.consumer;

import io.github.seamcarving.RgbaImage;

final class ConsumerApiProbe {
    static RgbaImage onePixel() {
        return new RgbaImage(1, 1, new byte[] {0, 0, 0, (byte) 255});
    }
}
