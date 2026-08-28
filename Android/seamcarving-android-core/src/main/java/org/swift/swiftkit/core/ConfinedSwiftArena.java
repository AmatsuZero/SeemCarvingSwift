package org.swift.swiftkit.core;

import java.util.ArrayList;
import java.util.List;

final class ConfinedSwiftArena implements ClosableSwiftArena {
    private final List<Runnable> destroyActions = new ArrayList<>();

    @Override
    public synchronized void register(JNISwiftInstance instance) {
        destroyActions.add(instance.$createDestroyFunction());
    }

    @Override
    public synchronized void close() {
        for (Runnable destroyAction : destroyActions) {
            destroyAction.run();
        }
        destroyActions.clear();
    }
}
