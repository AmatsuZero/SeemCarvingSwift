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
  :seamcarving-android
      \-- public Kotlin facade + private generated JNI binding + native libs
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

The public API is Kotlin-only. Generated `swift-java` wrappers, JNI classes,
Swift runtime details, and native-library loading remain implementation details.
This preserves the public contract if the bridge generation mechanism changes.

## Public API Contract

The Android AAR publicly provides:

- `RgbaImage`, with validated `width`, `height`, and RGBA8 bytes;
- `Mask` and `ResizeRequest` values that map to Core semantics;
- `SeamCarver` suspend operations for resize and supported mask workflows;
- a `Flow<ResizeProgress>` or equivalent progress surface;
- Kotlin cancellation mapped to Core cooperative cancellation;
- `Bitmap` convenience extensions that delegate to `RgbaImage`; and
- `SeamCarvingException`, which maps Core failures without exposing JNI or Swift
  exception types.

Public `RgbaImage` bytes are upright, origin-zero, straight-alpha, row-major
RGBA8. Construction rejects data whose size is not `width * height * 4`.

`Bitmap` conversion uses `Bitmap.getPixels()` and `Bitmap.setPixels()` with an
explicit `AARRGGBB` to/from `RGBA8` conversion. This establishes correct channel
and alpha semantics without depending on Android memory byte order. Decoding,
EXIF orientation normalization, and image-file encoding remain Android-side
responsibilities; convenience decoding may later provide an explicit upright
decoder, but no implicit orientation assumption is part of the Core contract.

All public carving calls run off Android's main thread. The first release uses
only the Core CPU backend. Later acceleration may change internals but must not
change the deterministic CPU result contract.

## Platform and Packaging Contract

The first release has `minSdk = 28` and packages `arm64-v8a`, `armeabi-v7a`,
and `x86_64`. Each AAR includes the Android bridge and every required Swift
runtime `.so` for each ABI. Its POM declares Java/Kotlin runtime dependencies
needed by the private swift-java binding transitively.

The build locks the exact compatible versions of the open-source Swift
toolchain, Swift Android SDK, Android NDK, and swift-java. They are release
build dependencies, not requirements placed on Gradle consumers.

## Build and Publication

Gradle owns the release workflow:

1. Build `SeamCarvingAndroidBridge` as a shared library for every ABI with the
   pinned Swift toolchain and Android SDK.
2. Generate and compile the private swift-java/JNI binding.
3. Assemble the bridge, Swift runtime libraries, and generated binding into a
   release AAR.
4. Use `maven-publish` to create the POM, source JAR, signatures, and a local
   Maven publication for verification.
5. On a signed release tag, publish the verified release to Maven Central.
   GitHub Packages may provide a private-preview channel, but is not the primary
   public distribution path.

## Verification

Three independent gates are required:

1. **Swift cross-host gate:** build `SeamCarvingCore` for every published ABI
   and execute the Core fixture suite on an Android emulator or device. Results
   must match canonical macOS fixture bytes.
2. **Android library gate:** test Kotlin RGBA entry points, mask behavior,
   failures, cancellation, progress, and `Bitmap` channel/alpha conversion.
3. **Consumer gate:** build and run a clean Compose sample that resolves only
   `io.github.seamcarving:seamcarving-android:<version>` from a Maven repository.
   This proves the POM and AAR include all runtime requirements and no local
   Swift/NDK setup leaks to consumers.

## Compatibility and Evolution

Version the public Kotlin API semantically. Do not publish generated bindings
as stable API. Do not expand `SeamCarvingCore` with Android imports or
platform-conditionals. Android-specific concerns remain in the bridge and
Gradle library layers. A future GPU backend, face detector, or Android editor
is a separate design and implementation effort.
