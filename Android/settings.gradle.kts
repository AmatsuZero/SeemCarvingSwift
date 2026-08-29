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
        google()
        mavenCentral()
    }
}

rootProject.name = "SeamCarvingAndroid"
include(":swiftkit-core")
include(":seamcarving-android-bridge")
include(":seamcarving-android-core")
include(":seamcarving-android-bitmap")
