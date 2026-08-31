import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.tasks.testing.Test
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    id("com.seamcarving.android.publish")
}

description = "Android Bitmap adapters for SeamCarving"

extensions.configure<LibraryExtension> {
    namespace = "io.github.seamcarving.bitmap"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 28
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    api(project(":seamcarving-android-core"))
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

tasks.withType<Test>().configureEach {
    if (name == "testReleaseUnitTest") {
        dependsOn("bundleReleaseAar")
        systemProperty(
            "releaseAar",
            layout.buildDirectory.file(
                "outputs/aar/seamcarving-android-bitmap-release.aar",
            ).get().asFile,
        )
    } else {
        exclude("**/BitmapAarContentsTest.class")
    }
}
