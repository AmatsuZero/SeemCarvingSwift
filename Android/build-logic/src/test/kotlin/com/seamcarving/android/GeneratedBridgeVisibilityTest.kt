package com.seamcarving.android

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertFalse

class GeneratedBridgeVisibilityTest {
    @Test
    fun hidesEveryUnknownTopLevelGeneratedTypeWithoutChangingMembers() {
        val generated = """
            package io.github.seamcarving;

            public final class FutureGeneratedBridge {
              public static void call() {}
            }

            public interface FutureGeneratedProtocol {
              void call();
            }
        """.trimIndent()

        val restricted = restrictGeneratedBridgeApi(generated)

        assertFalse(restricted.contains("public final class FutureGeneratedBridge"))
        assertFalse(restricted.contains("public interface FutureGeneratedProtocol"))
        assertContains(restricted, "final class FutureGeneratedBridge")
        assertContains(restricted, "interface FutureGeneratedProtocol")
        assertContains(restricted, "  public static void call() {}")
    }
}
