package org.swift.swiftkit.core;

import java.util.concurrent.atomic.AtomicBoolean;

public interface JNISwiftInstance {
    long $memoryAddress();
    AtomicBoolean $statusDestroyedFlag();
    long $typeMetadataAddress();
    Runnable $createDestroyFunction();
}
