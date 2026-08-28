package org.swift.swiftkit.core;

public final class SwiftObjects {
    private SwiftObjects() {}

    public static void requireNonZero(long pointer, String message) {
        if (pointer == 0) {
            throw new IllegalArgumentException(message);
        }
    }

    public static void destroy(long pointer, long typeMetadata) {}

    public static String toString(long pointer, long typeMetadata) {
        return "Swift object at " + pointer;
    }

    public static String toDebugString(long pointer, long typeMetadata) {
        return toString(pointer, typeMetadata);
    }
}
