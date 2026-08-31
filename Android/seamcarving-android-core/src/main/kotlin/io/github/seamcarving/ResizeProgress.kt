package io.github.seamcarving

data class ResizeProgress(
    val completedEdits: Int,
    val totalEdits: Int,
    val width: Int,
    val height: Int,
)
