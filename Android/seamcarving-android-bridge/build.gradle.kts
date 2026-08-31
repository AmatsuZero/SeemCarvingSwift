import org.gradle.api.tasks.compile.JavaCompile

plugins {
    `java-library`
    `maven-publish`
}

group = "io.github.seamcarving"
version = providers.gradleProperty("VERSION_NAME").get()

val coreProject = project(":seamcarving-android-core")
val generatedBridgeSources = coreProject.layout.buildDirectory.dir("generated/swift-java")

sourceSets.main {
    java.srcDir(generatedBridgeSources)
}

dependencies {
    implementation(project(":swiftkit-core"))
}

tasks.withType<JavaCompile>().configureEach {
    dependsOn(":seamcarving-android-core:generateSwiftJavaBindings")
    options.release.set(11)
}

tasks.jar {
    archiveBaseName.set("seamcarving-android-bridge")
}

java {
    withSourcesJar()
}

tasks.named("sourcesJar") {
    dependsOn(":seamcarving-android-core:generateSwiftJavaBindings")
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            artifactId = "seamcarving-android-bridge"
            from(components["java"])
        }
    }
    repositories {
        maven {
            name = "Build"
            url = uri(rootProject.layout.buildDirectory.dir("local-maven"))
        }
    }
}
