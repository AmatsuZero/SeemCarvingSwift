import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.tasks.testing.Test
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    id("com.seamcarving.android.publish")
}

description = "Default SeamCarving Android facade with RGBA and Bitmap APIs"

extensions.configure<LibraryExtension> {
    namespace = "io.github.seamcarving.facade"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 28
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    api(project(":seamcarving-android-core"))
    api(project(":seamcarving-android-bitmap"))
    testImplementation(libs.junit)
}

tasks.withType<Test>().configureEach {
    if (name == "testReleaseUnitTest") {
        val versionName = providers.gradleProperty("VERSION_NAME").get()
        dependsOn(rootProject.tasks.named("publishAllPublicationsToBuildRepository"))
        systemProperty("localMavenRepository", rootProject.layout.buildDirectory.dir("local-maven").get().asFile)
        systemProperty("seamcarvingVersion", versionName)
    }
}
