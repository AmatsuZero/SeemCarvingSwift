# Task 3 Report: Android RGBA API Review Fixes

## Status

Complete. The Android library now builds and packages the real generated
Swift-Java runtime, stages a strict native dependency closure for debug and
release, keeps generated Java classes outside the core AAR, and passes clean
connected JNI, release-boundary, and external Maven-consumer verification.

## Reviewer findings resolved

- **Real Swift destruction:** removed all checked-in no-op SwiftKit stubs. The
  generated source set now includes the pinned swift-java runtime ownership
  classes, whose `SwiftObjects.destroy` path calls native destruction. A
  connected test holds a real generated Swift result in `SwiftArena`, closes
  the arena, and observes the Swift object's native destroyed flag change.
- **No hard-coded generated output:** SwiftPM uses the module-local
  `build/swiftpm` scratch directory. The generation task locates the unique
  semantic JExtractSwift output and pinned swift-java checkout beneath that
  scratch directory, then copies the required sources into
  `build/generated/swift-java`.
- **Pinned Swiftly invocation:** generation and every Android cross-build run
  `swiftly run swift +6.3.3 ...` and depend on toolchain verification.
- **Debug and release JNI task graphs:** both `mergeDebugJniLibFolders` and
  `mergeReleaseJniLibFolders` depend on all three ABI staging tasks. A dry run
  from a clean module showed generation, serialized ABI builds, staging, and
  both merge tasks in the graph.
- **Public package:** the Kotlin API is `io.github.seamcarving`. The AAR test
  verifies all five public API classes are emitted there and that no legacy
  `com/seamcarving/android/core` bytecode remains.
- **Internal generated API:** JExtract emits the bridge into the facade's
  `io.github.seamcarving` JVM package and the build rewrites every generated
  top-level bridge class to package-private. This lets the same-package Kotlin
  implementation call it without making it consumer-visible. The bridge is a
  separate runtime-only Maven JAR; the core AAR contains neither generated
  bridge classes nor `org.swift.swiftkit.core` classes. The obsolete checked-in
  SwiftKit stub surface was deleted.
- **Hermetic package migration:** before JExtract runs, Gradle removes SwiftPM's
  incremental plugin output directory. This prevents source files from an old
  `javaPackage` value from surviving beside the current bindings. The release
  regression rejects any legacy `io.github.seamcarving.internal` bridge class.
- **Resolvable non-conflicting runtime coordinates:** the pinned Android subset
  of upstream SwiftKitCore retains upstream's canonical component identity,
  `org.swift.swiftkit:swiftkit-core:1.0-SNAPSHOT`. Core and bridge POMs depend
  on that exact runtime component. An external Android application declares
  the same official GAV directly and through core, then proves Gradle resolves
  exactly one component and passes Android's duplicate-class/dex gates using
  only the task-local Maven fixture.
- **Strict `DT_NEEDED` closure:** for each ABI, staging recursively scans the
  bridge and every copied library with the pinned NDK's `llvm-readelf`.
  Dependencies are copied from the bridge output, Swift runtime, or NDK C++
  runtime. A dependency is treated as a system library only when the exact
  file exists in the API-28 NDK sysroot. A final rescan fails the build on any
  unresolved edge and explicitly requires `libswiftCore.so` and
  `libSwiftJava.so`.
- **Cancellation:** `CancellationException` is rethrown unchanged. Wrapped
  cancellation from `CompletableFuture` is recursively unwrapped before the
  coroutine is resumed, and the native boundary catches `Exception` rather
  than `Throwable`.

## TDD and debugging evidence

The original attempt copied all SwiftKitCore Java sources. Android compilation
failed because annotation/runtime helpers referenced unavailable `jdk.jfr`
types. The smallest sufficient ownership/runtime source closure was selected
instead; it retains the real native cleanup implementation and excludes those
unneeded host-only helpers. A targeted cancellation test was added before the
unwrap fix and covers `CompletionException(CancellationException)` identity.

The first task-graph dry run found a self-cycle in the x86 build ordering. The
previous task provider is now captured before registering each next ABI build;
the corrected graph passes.

The boundary regression was then extended before the final fix. Against the
in-progress implementation it failed 3 of 8 tests: one for stale
`io.github.seamcarving.internal` classes, one for the colliding upstream
snapshot coordinate, and one for the incorrect POM dependency. Clearing the
SwiftPM plugin output at its source initially made the same 8 tests pass. The
later publication-boundary review correctly found that a second GAV cannot be
deduplicated against the upstream runtime, so the final fix uses the upstream
component identity and exercises that dependency graph in an external app.

## Verification

Environment:

- Android SDK: `/Users/samzhjiang/Library/Android/sdk`
- Pinned Android NDK: Swift 6.3.3 Android SDK bundle, NDK r27d
- Connected device: `Pixel_3a_API_33_arm64-v8a (AVD)`, Android 13

Clean decisive verification:

```text
ANDROID_HOME=/Users/samzhjiang/Library/Android/sdk \
ANDROID_NDK_HOME=/Users/samzhjiang/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d \
rtk ./gradlew clean \
  :seamcarving-android-core:connectedDebugAndroidTest \
  :seamcarving-android-core:testReleaseUnitTest \
  :seamcarving-android-core:verifyExternalMavenConsumer --no-daemon
```

Result: `BUILD SUCCESSFUL in 41m 52s`; 120 actionable tasks (106 executed, 14
up-to-date). All three native builds and strict closure stages completed:
`arm64-v8a`, `armeabi-v7a`, and `x86_64`. Debug connected tests passed 2/2:
canonical 2x2-to-1x2 JNI parity and real Swift arena destruction. Release JVM
tests passed 8/8: cancellation 1, RGBA validation 3, and AAR/POM boundary 4.
The nested external consumer build passed 35/35 actionable tasks, assembled a
debug APK, and resolved core, bridge, and SwiftKit runtime from
`Android/build/local-maven` without project dependencies.

After tightening the generator boundary check and bumping its declared
post-processor input, the connected, release, and external-consumer gates were
run once more without relying on the earlier generator output. The generator
reran, the connected tests still passed 2/2, the release suite still passed
8/8, and the nested consumer still passed 35/35 tasks. The combined build was
`BUILD SUCCESSFUL in 2m 9s` with 117 actionable tasks (103 executed, 14
up-to-date).

Additional verification:

- `rtk ./gradlew :seamcarving-android-core:mergeDebugJniLibFolders
  :seamcarving-android-core:mergeReleaseJniLibFolders --dry-run --no-daemon`
  — passed; both variants include generation plus all ABI build/stage tasks.
- `rtk swiftly run swift +6.3.3 test --filter AndroidResizeBridgeTests` — passed,
  1 test, 0 failures.
- Release AAR inspection found `classes.jar` and 17 native libraries for each
  of `arm64-v8a`, `armeabi-v7a`, and `x86_64`, including the bridge,
  `libSwiftJava.so`, `libswiftCore.so`, `libc++_shared.so`, and the required
  transitive Swift/Foundation runtime closure.
- `rtk git diff --check` — passed.

## Final publication-boundary closure (2026-08-29)

This section supersedes the earlier project-owned-coordinate experiment.

- `swiftkit-core` now derives the pinned SwiftJava 0.2.0 runtime sources while
  retaining the exact upstream `org.swift.swiftkit:swiftkit-core:1.0-SNAPSHOT`
  GAV. The staging task verifies that group, artifact, and version still match
  the pinned upstream Gradle declaration before compiling or publishing the
  local test fixture.
- The Maven-only Android fixture declares both
  `io.github.seamcarving:seamcarving-android-core:0.1.0-SNAPSHOT` and the
  official SwiftKit GAV. Its verification requires exactly one SwiftKit module
  component, rejects the obsolete project-owned runtime artifact, and then
  runs `checkDebugDuplicateClasses`, dexing, and APK assembly.
- `FutureAwaiter` is a file-private top-level object. The release test reads
  class access flags and runs `javap -public`, allowing only the five intended
  facade types and rejecting the former public `SeamCarverKt.awaitResult`
  surface. Cancellation still preserves the original wrapped
  `CancellationException` instance.
- Generated JExtract ownership is name-independent: a tested post-processor
  removes public ownership from every top-level Java class, interface, enum,
  record, or annotation while retaining public members for same-package Kotlin
  calls. Artifact inspection checks every generated top-level class, and a
  consumer compilation probe confirms bridge types are inaccessible.

Fresh evidence from the final boundary diff:

- Generator mutation RED: with the generic post-processor bypassed,
  `GeneratedBridgeVisibilityTest` failed at its first visibility assertion;
  restored implementation GREEN: 1/1 passed with all 12 build-logic tasks
  executed.
- Facade mutation RED: changing `FutureAwaiter` back from `private` to
  `internal` caused both the cancellation visibility assertion and release
  AAR public-type allowlist to fail; restoring `private` returns the same 8
  release tests to GREEN.
- `:seamcarving-android-core:connectedDebugAndroidTest`: `BUILD SUCCESSFUL in
  42s`; 2/2 tests, zero failures/errors on Android 13 ARM64.
- `:seamcarving-android-core:testReleaseUnitTest --rerun`: final GREEN was
  `BUILD SUCCESSFUL in 22s`; 8/8 tests, zero failures/errors (4 AAR/POM
  boundary, 3 validation, 1
  cancellation).
- `:seamcarving-android-core:verifyExternalMavenConsumer`: nested Maven-only
  build `BUILD SUCCESSFUL in 37s`; 35/35 tasks executed, including one-component
  resolution, duplicate-class checking, dexing, and APK assembly.
- `swiftly run swift +6.3.3 test --filter AndroidResizeBridgeTests`: 1/1 test,
  zero failures.
