import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.publish.PublishingExtension
import org.gradle.api.publish.maven.MavenPublication
import org.gradle.kotlin.dsl.configure
import org.gradle.kotlin.dsl.create

pluginManager.apply("maven-publish")

group = "io.github.seamcarving"
version = providers.gradleProperty("VERSION_NAME").get()

extensions.configure<LibraryExtension> {
    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

afterEvaluate {
    extensions.configure<PublishingExtension> {
        publications {
            create<MavenPublication>("release") {
                artifactId = project.name
                from(components.getByName("release"))
                pom {
                    name.set(project.name)
                    description.set(project.description ?: "SeamCarving Android library module")
                    url.set("https://github.com/AmatsuZero/SeemCarvingSwift")
                    scm {
                        connection.set("scm:git:https://github.com/AmatsuZero/SeemCarvingSwift.git")
                        developerConnection.set("scm:git:ssh://git@github.com/AmatsuZero/SeemCarvingSwift.git")
                        url.set("https://github.com/AmatsuZero/SeemCarvingSwift")
                    }
                }
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
