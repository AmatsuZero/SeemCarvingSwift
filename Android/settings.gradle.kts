pluginManagement {
    includeBuild("build-logic")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven {
            name = "SeamCarvingBuild"
            url = uri(rootDir.resolve("build/local-maven"))
        }
        google()
        mavenCentral()
    }
}

rootProject.name = "SeamCarvingAndroid"
include(":swiftkit-core")
include(":seamcarving-android-bridge")
include(":seamcarving-android-core")
include(":seamcarving-android-bitmap")
include(":seamcarving-android-mlkit")
include(":seamcarving-android")
include(":sample")
