# Task 2 Report: Assemble the all-ABI core AAR

## Status

Blocked; no commit was created. The scoped implementation and the required
release-AAR unit test are present, but the complete all-ABI Gradle verification
has not passed.

## Files changed

- `Android/build-logic/build.gradle.kts`
  - Adds the Android Gradle Plugin implementation dependency used by the
    precompiled native-library convention.
- `Android/build-logic/src/main/kotlin/com.seamcarving.android.native-library.gradle.kts`
  - Applies the Android library and pinned toolchain conventions.
  - Defines the exact requested ABI/triple map, release Swift build tasks, and
    per-ABI native staging under `build/generated/jniLibs/<abi>`.
  - Copies the bridge, NDK `libc++_shared.so`, and the recursively discovered
    Swift ELF dependencies only; the generated directory is attached to the
    core module's `jniLibs` source set.
- `Android/seamcarving-android-core/build.gradle.kts`
  - Applies the native-library convention and configures the release unit-test
    AAR input.
- `Android/seamcarving-android-core/src/main/AndroidManifest.xml`
  - Adds the Android library manifest.
- `Android/seamcarving-android-core/src/test/java/com/seamcarving/android/core/ReleaseAarContentsTest.java`
  - Opens the real release AAR and asserts bridge, `libc++_shared.so`, and
    `libswiftCore.so` for arm64-v8a, armeabi-v7a, and x86_64.

## TDD and verification evidence

1. The first executable unit-test run was red as intended:
   `:seamcarving-android-core:testReleaseUnitTest` compiled the test and failed
   with `Missing jni/arm64-v8a/libSeamCarvingAndroidBridge.so` from the actual
   release AAR.
2. The native-library convention compiles and configures successfully:
   `:seamcarving-android-core:tasks --all` showed all three release build and
   staging tasks.
3. The requested full command was started with the installed Android SDK and
   the pinned Android NDK:
   `./gradlew :seamcarving-android-core:assembleRelease :seamcarving-android-core:testReleaseUnitTest`.
   It completed the arm64 `SeamCarvingAndroidBridge` target after SwiftJava's
   first-build compilation, then failed staging because `--target` compiles the
   module without emitting the dynamic product at the expected path.
4. The convention was corrected to use `--product SeamCarvingAndroidBridge`.
   The follow-up product build was still compiling when the foreground tool
   window expired; its verified orphaned `swiftly`/`swift-build` processes were
   terminated to release `.build/plugin-tools.db`.

## Commit

None. The task instruction requires a commit only after the specified all-ABI
build and unit test pass.

## Spec and quality verdict

Implementation structure is aligned with the requested files, ABI/triple map,
release mode, staging location, and AAR-content test. It is not complete: there
is no fresh passing evidence for the corrected product output, all three ABI
stages, or the requested release AAR/unit-test command.

## Blockers

- SwiftJava/JExtract's first release cross-build is long-running (the arm64
  target alone took about nine minutes before staging).
- The verification harness terminates foreground commands around the tool-call
  window without reaping Swift child processes, which leaves SwiftPM's
  `plugin-tools.db` locked. Retained background terminal sessions avoid that
  timeout, but the final corrected `--product` all-ABI run still needs to be
  allowed to complete and its AAR test result captured.

## Verification / integration round 1

1. Confirmed no process held `.build/plugin-tools.db` before resuming. An
   active compiler process was observed during one check, so no lock file or
   live process was removed.
2. Reproduced the native-build-system artifact issue: both
   `swift build --build-system native --product SeamCarvingAndroidBridge` and
   the earlier target build complete without `libSeamCarvingAndroidBridge.so`;
   only `libSwiftJava.so` is present in the target release directory.
3. A retained, serial arm64 experiment using the same pinned SDK and
   `swift build --swift-sdk aarch64-unknown-linux-android28 --configuration release --product SeamCarvingAndroidBridge`
   (without `--build-system native`) passed after 277.02 seconds and emitted
   `.build/aarch64-unknown-linux-android28/release/libSeamCarvingAndroidBridge.so`.
4. The convention was updated to use that proven product invocation. The
   subsequent Gradle `stageSwiftArm64V8aNativeLibraries` run is active in a
   retained terminal pane; armv7, x86_64, and the final AAR inspection have not
   yet completed, so there is still no commit.

## Final verification

All serial native-staging tasks passed with the corrected SwiftPM product
invocation:

- arm64-v8a: `stageSwiftArm64V8aNativeLibraries` — passed (5m 09s)
- armeabi-v7a: `stageSwiftArmeabiV7aNativeLibraries` — passed (8m 59s)
- x86_64: `stageSwiftX8664NativeLibraries` — passed (8m 43s)

Fresh required Gradle verification also passed:

```text
./gradlew :seamcarving-android-core:assembleRelease \
  :seamcarving-android-core:testReleaseUnitTest
BUILD SUCCESSFUL in 21s
```

The AAR inspection test passed after opening the release AAR and asserting the
bridge, NDK C++ runtime, and `libswiftCore.so` for each requested ABI.

## Final verdict

Complete. The convention uses the exact required ABI/triple map, builds the
dynamic bridge product in release, recursively stages only its required Swift
ELF runtime dependencies plus `libc++_shared.so`, and packages them only from
the core module's generated `jniLibs` directory. No later module packages a
runtime.

## Commit

`f525178 feat: assemble all-ABI Android core AAR`
