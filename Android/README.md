# SeamCarving for Android

The Android distribution is split into Gradle artifacts so applications only
pull the capabilities they use. Consumers do not need Swift, the Swift Android
SDK, or the Android NDK; those are build-time requirements for this repository.

## Gradle coordinates

Use the default facade for the RGBA core plus `Bitmap` adapters:

```kotlin
dependencies {
    implementation("io.github.seamcarving:seamcarving-android:<version>")
}
```

The individual artifacts are:

| Coordinate | Capability |
| --- | --- |
| `io.github.seamcarving:seamcarving-android-core` | CPU-backed RGBA, masks, progress, and cancellation |
| `io.github.seamcarving:seamcarving-android-bitmap` | Android `Bitmap` conversion and resize helpers |
| `io.github.seamcarving:seamcarving-android` | Default facade: core + Bitmap |
| `io.github.seamcarving:seamcarving-android-mlkit` | Optional ML Kit face-protection masks |

ML Kit is deliberately excluded from the default facade. Add its coordinate
explicitly when face detection is required:

```kotlin
dependencies {
    implementation("io.github.seamcarving:seamcarving-android:<version>")
    implementation("io.github.seamcarving:seamcarving-android-mlkit:<version>")
}
```

All release AARs include source JARs. Native Swift and C++ libraries for
`arm64-v8a`, `armeabi-v7a`, and `x86_64` are packaged only in the core AAR.

## Local publication and consumer verification

From this directory, publish the full dependency graph to
`build/local-maven`:

```sh
./gradlew publishAllPublicationsToBuildRepository
```

The `sample` build resolves only Maven coordinates. It has no Gradle project
dependencies and its standalone verification intentionally removes Swift and
NDK environment variables:

```sh
./gradlew verifyExternalMavenSample
```

The local publication tasks never upload to a remote repository.
