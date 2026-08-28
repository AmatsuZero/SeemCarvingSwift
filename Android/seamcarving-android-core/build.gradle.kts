import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.seamcarving.android.native-library")
    alias(libs.plugins.kotlin.android)
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_1_8)
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

tasks.withType<Test>().configureEach {
    if (name == "testReleaseUnitTest") {
        dependsOn("bundleReleaseAar")
        systemProperty("releaseAar", layout.buildDirectory.file("outputs/aar/seamcarving-android-core-release.aar").get().asFile)
    } else {
        exclude("**/ReleaseAarContentsTest.class")
    }
}
