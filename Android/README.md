# SeamCarving for Android

The Android distribution is split into Gradle artifacts so applications only
pull the capabilities they use. Consumers do not need Swift, the Swift Android
SDK, or the Android NDK; those are build-time requirements for this repository.

The first Android surface is CPU-only, supports Android API 28 and newer, and
ships native code only for `arm64-v8a`, `armeabi-v7a`, and `x86_64`. The
published Kotlin API is stable; generated Java/JNI bindings and Swift runtime
types are implementation details and must not be imported by an app.

## Gradle coordinates

Use the default facade for the RGBA core plus `Bitmap` adapters:

```kotlin
repositories {
    mavenCentral() // once the selected version has been released
}

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

Every published release coordinate includes a separate sources JAR. Native Swift and C++ libraries for
`arm64-v8a`, `armeabi-v7a`, and `x86_64` are packaged only in the core AAR.

## Repository and release status

The coordinates above become consumable from Maven Central only after the
signed remote release workflow has published that exact version. This repository
does **not** upload Maven artifacts from its regular CI or local tasks. Until a
version is released, use the local publication only for repository development:

```kotlin
repositories {
    maven { url = uri("/absolute/path/to/SeemCarvingSwift/Android/build/local-maven") }
    google()
    mavenCentral()
}
```

Do not ship that filesystem repository configuration in an application. Normal
consumers use the released Maven Central coordinates and receive the transitive
Swift runtime through `seamcarving-android-core`.

## Pixel, mask, and thread semantics

`RgbaImage(width, height, bytes)` represents upright, origin-zero,
row-major, straight-alpha RGBA8 pixels. Its byte count must be exactly
`width * height * 4`; invalid dimensions, byte counts, target sizes, or mask
sizes throw `IllegalArgumentException` before JNI is entered.

`Mask` values are finite floats in the inclusive `0f..1f` range and must have
the exact source width and height. A protection mask gives pixels a high cost;
a removal mask gives them a low cost. A mask does not move independently of its
source image—pass a mask built for the image you are resizing.

All public resize work is dispatched away from Android's main thread. A simple
RGBA resize therefore needs no platform image dependency:

```kotlin
import io.github.seamcarving.RgbaImage
import io.github.seamcarving.ResizeRequest
import io.github.seamcarving.SeamCarver

val output = SeamCarver().resize(
    ResizeRequest(source, targetWidth = 640, targetHeight = 480),
)
```

`resizeWithProgress` returns a Kotlin `Flow<ResizeProgress>`. Collect it in a
coroutine you own; cancelling that coroutine cooperatively cancels the native
operation and prevents further progress delivery:

```kotlin
viewModelScope.launch {
    SeamCarver().resizeWithProgress(request).collect { progress ->
        updateProgress(progress.completedEdits, progress.totalEdits)
    }
}
// Cancel the owning Job when the user presses Cancel.
```

## Bitmap adapter

`seamcarving-android-bitmap` converts with `Bitmap.getPixels()` and
`Bitmap.setPixels()`, explicitly mapping Android `AARRGGBB` integers to/from
RGBA8. This avoids raw-memory byte-order and row-stride assumptions. Only
`Bitmap.Config.ARGB_8888` is accepted. Conversion reads but never mutates or
recycles the caller's source; returned bitmaps are new mutable caller-owned
objects.

```kotlin
import io.github.seamcarving.bitmap.seamCarveTo

val resized = bitmap.seamCarveTo(width = 640, height = 480)
```

Normalize image-file orientation during Android decoding before conversion if
your source can carry EXIF orientation. The adapter receives already-upright
pixels and intentionally does not decode or encode files.

## Optional ML Kit face protection

`seamcarving-android-mlkit` owns Android face detection entirely; Swift does
not import ML Kit. It produces an all-zero mask when no face is found, clamps
face rectangles to the image bounds, and turns detector failures into
`SeamCarvingException` while preserving their cause.

```kotlin
import io.github.seamcarving.bitmap.seamCarveTo
import io.github.seamcarving.mlkit.detectFaceProtectionMask

val faceProtection = bitmap.detectFaceProtectionMask()
val resized = bitmap.seamCarveTo(
    width = 640,
    height = 480,
    protectionMask = faceProtection,
)
```

ML Kit is intentionally absent from `seamcarving-android`; add its artifact
only for applications that need face detection.

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

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `UnsatisfiedLinkError` on a device | Use `minSdk 28` and a supported ABI; depend on the facade or core AAR, not a copied adapter-only AAR. |
| `IllegalArgumentException` before resize | Check positive dimensions, exactly `width * height * 4` bytes, and masks matching the source size. |
| Wrong Bitmap colors or alpha | Use `ARGB_8888` and the provided conversion functions; do not wrap `Bitmap` storage as RGBA bytes. |
| Face detector classes missing | Add `seamcarving-android-mlkit` explicitly; it is not a dependency of the default facade. |
| Local sample cannot resolve artifacts | Run `./gradlew publishAllPublicationsToBuildRepository`, then use `./gradlew verifyExternalMavenSample`; it resolves only `build/local-maven` coordinates. |
| Repository build reports a toolchain error | The library build (not the consumer) requires Swift 6.3.3, `swift-6.3.3-RELEASE_android`, and NDK `27.3.13750724`; run `./gradlew :seamcarving-android-core:verifySwiftAndroidToolchain`. |
