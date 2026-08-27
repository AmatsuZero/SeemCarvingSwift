plugins {
    id("com.seamcarving.android.native-library")
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

tasks.withType<Test>().configureEach {
    if (name == "testReleaseUnitTest") {
        dependsOn("bundleReleaseAar")
        systemProperty("releaseAar", layout.buildDirectory.file("outputs/aar/seamcarving-android-core-release.aar").get().asFile)
    }
}
