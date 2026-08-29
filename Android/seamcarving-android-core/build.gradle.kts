import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.tasks.Exec
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.gradle.jvm.tasks.Jar
import org.gradle.api.publish.maven.MavenPublication

plugins {
    id("com.seamcarving.android.native-library")
    alias(libs.plugins.kotlin.android)
    `maven-publish`
}

group = "io.github.seamcarving"
version = providers.gradleProperty("VERSION_NAME").get()

extensions.configure<LibraryExtension> {
    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":swiftkit-core"))
    implementation(project(":seamcarving-android-bridge"))
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

tasks.withType<Test>().configureEach {
    if (name == "testReleaseUnitTest") {
        val swiftKitRuntimeJar = project(":swiftkit-core")
            .tasks.named<Jar>("jar")
            .flatMap { it.archiveFile }
        val bridgeRuntimeJar = project(":seamcarving-android-bridge")
            .tasks.named<Jar>("jar")
            .flatMap { it.archiveFile }
        dependsOn(
            swiftKitRuntimeJar,
            bridgeRuntimeJar,
            ":swiftkit-core:publishMavenPublicationToBuildRepository",
            ":seamcarving-android-bridge:publishMavenPublicationToBuildRepository",
            "publishReleasePublicationToBuildRepository",
        )
        dependsOn("bundleReleaseAar")
        systemProperty("releaseAar", layout.buildDirectory.file("outputs/aar/seamcarving-android-core-release.aar").get().asFile)
        systemProperty("swiftKitRuntimeJar", swiftKitRuntimeJar.get().asFile)
        systemProperty(
            "swiftKitRuntimeCoordinate",
            "org.swift.swiftkit:swiftkit-core:1.0-SNAPSHOT",
        )
        systemProperty("bridgeRuntimeJar", bridgeRuntimeJar.get().asFile)
        val localMaven = rootProject.layout.buildDirectory.dir("local-maven").get().asFile
        val versionName = providers.gradleProperty("VERSION_NAME").get()
        systemProperty(
            "corePomDirectory",
            localMaven.resolve("io/github/seamcarving/seamcarving-android-core/$versionName"),
        )
        systemProperty(
            "bridgePomDirectory",
            localMaven.resolve("io/github/seamcarving/seamcarving-android-bridge/$versionName"),
        )
        systemProperty(
            "swiftKitPomDirectory",
            localMaven.resolve("org/swift/swiftkit/swiftkit-core/1.0-SNAPSHOT"),
        )
    } else {
        exclude("**/ReleaseAarContentsTest.class")
    }
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                artifactId = "seamcarving-android-core"
                from(components["release"])
            }
        }
        repositories {
            maven {
                name = "Build"
                url = uri(rootProject.layout.buildDirectory.dir("local-maven"))
            }
        }
    }
}

val coreMavenConsumer = layout.projectDirectory.dir("src/test/fixtures/maven-consumer")
tasks.register<Exec>("verifyExternalMavenConsumer") {
    group = "verification"
    description = "Builds an external Android app using only the locally published core Maven coordinate."
    dependsOn(
        ":swiftkit-core:publishMavenPublicationToBuildRepository",
        ":seamcarving-android-bridge:publishMavenPublicationToBuildRepository",
        "publishReleasePublicationToBuildRepository",
    )
    workingDir(coreMavenConsumer)
    inputs.dir(coreMavenConsumer)
    outputs.upToDateWhen { false }
    commandLine(
        rootProject.layout.projectDirectory.file("gradlew").asFile.absolutePath,
        "--no-daemon",
        "--refresh-dependencies",
        "-p",
        coreMavenConsumer.asFile.absolutePath,
        "clean",
        "assembleDebug",
        "verifyResolvedRuntime",
        "-PseamcarvingRepository=${rootProject.layout.buildDirectory.dir("local-maven").get().asFile.toURI()}",
        "-PseamcarvingVersion=$version",
    )
}
