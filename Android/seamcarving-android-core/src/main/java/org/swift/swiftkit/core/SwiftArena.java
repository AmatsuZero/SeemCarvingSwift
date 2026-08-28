package org.swift.swiftkit.core;

public interface SwiftArena {
    void register(JNISwiftInstance instance);

    static ClosableSwiftArena ofConfined() {
        return new ConfinedSwiftArena();
    }
}
