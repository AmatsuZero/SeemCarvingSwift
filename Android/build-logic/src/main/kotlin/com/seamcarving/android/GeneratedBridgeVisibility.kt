package com.seamcarving.android

private val topLevelPublicJavaType = Regex(
    pattern = "(?m)^public\\s+((?:(?:abstract|final|sealed|non-sealed|strictfp)\\s+)*(?:class|interface|enum|record|@interface)\\b)",
)

/**
 * Removes JVM-public ownership from every top-level Java type emitted by
 * JExtract while leaving public members available to the same-package Kotlin
 * facade. Generated members are indented; top-level declarations start in
 * column zero, which makes this independent of the generated type names.
 */
internal fun restrictGeneratedBridgeApi(source: String): String =
    source.replace(topLevelPublicJavaType, "$1")
