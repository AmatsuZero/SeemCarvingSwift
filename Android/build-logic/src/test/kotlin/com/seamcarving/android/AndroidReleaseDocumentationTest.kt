package com.seamcarving.android

import java.io.File
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertFalse

class AndroidReleaseDocumentationTest {
    @Test
    fun workflowUsesThePinnedBuildsSupportedJdk() {
        val workflow = repositoryRoot().resolve(".github/workflows/android-library.yml").readText()

        assertContains(workflow, "- name: Set up JDK 17")
        assertContains(workflow, "java-version: '17'")
        assertFalse(workflow.contains("JDK 25"))
        assertFalse(workflow.contains("java-version: '25'"))
    }

    @Test
    fun readmeDescribesSourcesAsSeparateMavenArtifacts() {
        val readme = repositoryRoot().resolve("Android/README.md").readText()

        assertContains(readme, "Every published release coordinate includes a separate sources JAR.")
        assertFalse(readme.contains("AARs include source JARs"))
    }

    private fun repositoryRoot(): File =
        generateSequence(File(System.getProperty("user.dir")).absoluteFile) { it.parentFile }
            .firstOrNull { it.resolve(".github/workflows/android-library.yml").isFile }
            ?: error("Could not locate the repository root from ${System.getProperty("user.dir")}")
}
