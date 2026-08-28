# Task 3 Report: Android RGBA API Review Fixes

## Status

Complete. The Android library now builds and packages the real generated
Swift-Java runtime, stages a strict native dependency closure for debug and
release, and passes connected JNI tests plus release AAR verification from a
clean module build.

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
- **Internal generated API:** the generated JNI bridge is emitted only in
  `io.github.seamcarving.internal`; public Kotlin signatures do not expose it.
  The obsolete checked-in SwiftKit stub surface was deleted.
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

## Verification

Environment:

- Android SDK: `/Users/samzhjiang/Library/Android/sdk`
- Pinned Android NDK: Swift 6.3.3 Android SDK bundle, NDK r27d
- Connected device: `Pixel_3a_API_33_arm64-v8a (AVD)`, Android 13

Clean decisive verification:

```text
ANDROID_HOME=/Users/samzhjiang/Library/Android/sdk \
ANDROID_NDK_HOME=/Users/samzhjiang/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d \
rtk ./gradlew :seamcarving-android-core:clean \
  :seamcarving-android-core:connectedDebugAndroidTest \
  :seamcarving-android-core:testReleaseUnitTest --no-daemon
```

Result: `BUILD SUCCESSFUL in 29m 31s`; 102 actionable tasks (93 executed, 9
up-to-date). All three native builds and strict closure stages completed:
`arm64-v8a`, `armeabi-v7a`, and `x86_64`. Debug connected tests passed 2/2:
canonical 2x2-to-1x2 JNI parity and real Swift arena destruction. Release JVM
tests passed 6/6: cancellation 1, RGBA validation 3, and AAR contents 2.

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
