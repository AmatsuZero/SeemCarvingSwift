package org.swift.swiftkit.core;

public interface ClosableSwiftArena extends SwiftArena, AutoCloseable {
    @Override
    void close();
}
