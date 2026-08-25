# Android Gradle Library Design

## Status

Approved design. This document defines the first Android delivery surface for
SeamCarvingSwift. It does not add an Android application or implementation.

## Goal

Publish a versioned Android library that external Android projects consume with
one Maven/Gradle dependency:

```kotlin
dependencies {
    implementation("io.github.seamcarving:seamcarving-android:<version>")
}
```

Consumers must not install Swift, the Android NDK, or manually copy an AAR or
native library. The published AAR contains all native libraries required to run
the supported API.

## Scope

The first release exposes both:

- a platform-neutral RGBA API for callers that own their pixel buffers; and
- Android `Bitmap` convenience APIs that use the same RGBA path internally.

It supports CPU seam carving, resize options, protection/removal masks,
progress, and cancellation. It does not include an Android editor application,
Android CLI, Android GPU backend, Apple-only pre-scaling, or automatic face
detection.

## Architecture

```text
Package.swift
  SeamCarvingCore
  SeamCarvingAndroidBridge
      \-- JNI-oriented Swift API; CPU Core only

Android Gradle build
  :seamcarving-android-core
      \-- RGBA public API + private generated JNI binding + native libs
  :seamcarving-android-bitmap
      \-- Android Bitmap adapter
  :seamcarving-android-mlkit
      \-- optional ML Kit face-protection adapter
  :seamcarving-android
      \-- default facade: core + bitmap; excludes ML Kit
  :sample
      \-- consumer verification only; never published
  build-logic
      \-- ABI build, packaging, and publication conventions

Maven
  io.github.seamcarving:seamcarving-android:<version>
```

`SeamCarvingAndroidBridge` depends only on `SeamCarvingCore`. It presents a
narrow, JNI-friendly interface rather than exposing the Core package's Swift
value types directly to Java. It is the only Swift target built into Android
native libraries.

The Android Gradle targets have equivalent capability boundaries to the Swift
package targets:

| Artifact | Dependencies | Responsibility |
| --- | --- | --- |
| `seamcarving-android-core` | Swift bridge | Public RGBA/mask API, options, native loading, and CPU carving. |
| `seamcarving-android-bitmap` | `android-core` | `Bitmap` conversion and other Android image adaptation. |
| `seamcarving-android-mlkit` | `android-bitmap`, ML Kit | Android face detection and conversion of its results to a protection mask. |
| `seamcarving-android` | `android-core`, `android-bitmap` | Default convenience facade; it intentionally does not include ML Kit. |

Generated `swift-java` wrappers, JNI classes, Swift runtime details, and native
library loading remain implementation details. This preserves the public
contract if the bridge generation mechanism changes.

## Public API Contract

`seamcarving-android-core` publicly provides:

- `RgbaImage`, with validated `width`, `height`, and RGBA8 bytes;
- `Mask` and `ResizeRequest` values that map to Core semantics;
- `SeamCarver` suspend operations for resize and supported mask workflows;
- a `Flow<ResizeProgress>` or equivalent progress surface;
- Kotlin cancellation mapped to Core cooperative cancellation;
- `SeamCarvingException`, which maps Core failures without exposing JNI or Swift
  exception types.

`seamcarving-android-bitmap` provides `Bitmap` convenience extensions that
delegate to the core RGBA API. `seamcarving-android` re-exports the standard
core and Bitmap experience for users who want one dependency.

Public `RgbaImage` bytes are upright, origin-zero, straight-alpha, row-major
RGBA8. Construction rejects data whose size is not `width * height * 4`.

`Bitmap` conversion in `seamcarving-android-bitmap` uses `Bitmap.getPixels()`
and `Bitmap.setPixels()` with an explicit `AARRGGBB` to/from `RGBA8` conversion.
This establishes correct channel and alpha semantics without depending on
Android memory byte order. Decoding, EXIF orientation normalization, and
image-file encoding remain Android-side responsibilities; convenience decoding
may later provide an explicit upright decoder, but no implicit orientation
assumption is part of the Core contract.

`seamcarving-android-mlkit` owns all Android face detection. It converts ML Kit
face boxes or landmarks into a Core-compatible protection mask, then calls the
same core RGBA API. Swift never imports Android or ML Kit types and does not
know whether a mask originated from face detection or from an application.

All public carving calls run off Android's main thread. The first release uses
only the Core CPU backend. Later acceleration may change internals but must not
change the deterministic CPU result contract.

## Platform and Packaging Contract

The first release has `minSdk = 28` and packages `arm64-v8a`, `armeabi-v7a`,
and `x86_64`. `seamcarving-android-core` includes the Android bridge and every
required Swift runtime `.so` for each ABI. Its POM declares Java/Kotlin runtime
dependencies needed by the private swift-java binding transitively. The Bitmap,
ML Kit, and default facade artifacts declare their capability dependencies in
their POMs; no artifact duplicates the Swift runtime libraries.

The build locks the exact compatible versions of the open-source Swift
toolchain, Swift Android SDK, Android NDK, and swift-java. They are release
build dependencies, not requirements placed on Gradle consumers.

## Build and Publication

Gradle owns the release workflow:

1. Build `SeamCarvingAndroidBridge` as a shared library for every ABI with the
   pinned Swift toolchain and Android SDK, and package it only in
   `seamcarving-android-core`.
2. Generate and compile the private swift-java/JNI binding.
3. Assemble the core AAR, Bitmap adapter AAR, optional ML Kit AAR, and default
   facade with their respective transitive POM dependencies.
4. Use `maven-publish` to create the POMs, source JARs, signatures, and local
   Maven publications for verification.
5. On a signed release tag, publish the verified artifact set to Maven Central.
   GitHub Packages may provide a private-preview channel, but is not the primary
   public distribution path.

## Verification

Three independent gates are required:

1. **Swift cross-host gate:** build `SeamCarvingCore` for every published ABI
   and execute the Core fixture suite on an Android emulator or device. Results
   must match canonical macOS fixture bytes.
2. **Android library gate:** test Kotlin RGBA entry points, mask behavior,
   failures, cancellation, progress, and `Bitmap` channel/alpha conversion.
3. **Consumer gate:** build and run clean Compose samples that resolve the
   default artifact and the ML Kit artifact solely from a Maven repository. This
   proves the POM graph, AAR contents, and optional dependency split include all
   runtime requirements and no local Swift/NDK setup leaks to consumers.

## Compatibility and Evolution

Version every public Kotlin artifact semantically. Do not publish generated
bindings as stable API. Do not expand `SeamCarvingCore` with Android imports or
platform-conditionals. Android-specific concerns remain in the bridge and
Gradle library layers. A future GPU backend or Android editor is a separate
design and implementation effort.
