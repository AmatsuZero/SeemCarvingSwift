# Task 1 Report: Pinned Android Swift Bridge Build

## Status

Blocked; no commit was created. The implementation is present in the assigned
worktree, but the required end-to-end checks have not completed successfully.

## Files changed

- `Package.swift`
  - Adds dynamic `SeamCarvingAndroidBridge` product and target.
  - The target depends only on `SeamCarvingCore` and pinned
    `SwiftJava` from `swift-java` `0.2.0`, and applies
    `JExtractSwiftPlugin`.
  - Adds `SeamCarvingAndroidBridgeTests`.
- `Package.resolved`
  - Resolves the exact `swift-java` `0.2.0` dependency graph.
- `Sources/SeamCarvingAndroidBridge/BridgeProbe.swift`
  - Implements the specified `[UInt8]` echo probe.
- `Tests/SeamCarvingAndroidBridgeTests/BridgeProbeTests.swift`
  - Asserts the required `[0, 1, 127, 255]` round trip.
- `Android/settings.gradle.kts`, `Android/build.gradle.kts`,
  `Android/gradle/libs.versions.toml`, `Android/gradle.properties`
  - Establish the Gradle root and pin Android/Swift-related versions.
- `Android/build-logic/settings.gradle.kts`, `Android/build-logic/build.gradle.kts`,
  `Android/build-logic/src/main/kotlin/com.seamcarving.android.toolchain.gradle.kts`
  - Add the convention plugin and its exact Swift `6.3.3`, SDK
    `swift-6.3.3-RELEASE_android`, and NDK `27.3.13750724` checks.
  - The plugin calls `swiftly --version`, `swiftly run swift +6.3.3 --version`,
    and `swiftly run swift +6.3.3 sdk list`, reads
    `ANDROID_NDK_HOME/source.properties`, and performs no installation/download.
  - Defines `buildSwiftArm64-v8a` for
    `aarch64-unknown-linux-android28`.
- `Android/seamcarving-android-core/build.gradle.kts`
  - Exposes the convention tasks under the required core module path.

## Tests and outputs

1. RED invocation: `swift test --filter SeamCarvingAndroidBridgeTests`
   began resolving the new package dependency before the bridge implementation
   existed. The initial attempt was interrupted by the terminal timeout during
   dependency setup, so it did not reach XCTest compilation.
2. First GREEN invocation with `swift-java` `0.1.2` failed before test
   compilation because that release requires macOS 15 while this package
   supports macOS 14. It was not retained.
3. A subsequent `0.1.2` attempt on macOS 15 failed while compiling upstream
   `JExtractSwiftLib` under Swift `6.3.3`, with errors including
   `cannot convert value of type '[Any]' to expected argument type
   '[JNISwift2JavaGenerator.OutParameter]'`.
4. The pin was revised to `swift-java` `0.2.0`, whose manifest supports macOS
   13 and uses Swift Syntax 603. Its first `swift test` build is still compiling
   the JExtract plugin dependency tree in this environment; no passing XCTest
   result or generated Java source was available before handoff.
5. Gradle verification could not start: neither `gradle` nor an `Android/gradlew`
   wrapper is available in the worktree/environment. `ANDROID_NDK_HOME` was also
   not configured for this session. Consequently, the convention task and
   `buildSwiftArm64-v8a` have not been run.

## Generated Java surface

Not verified. No `JExtractSwiftPlugin` generated Java output was available
because the compatible pinned dependency had not finished its first plugin
build. Therefore there is no evidence yet that `[UInt8]` maps to Java `byte[]`.
No alternate production transport was introduced.

## Commit

None, per the instruction to commit only when the scoped task completes.

## Spec-compliance verdict

Implementation structure is aligned with the requested files, bridge API, and
toolchain values, but the task is **not complete**: the required Swift test,
Gradle toolchain/ABI build, and generated Java `byte[]` proof remain unverified.

## Quality self-review

- The bridge has exactly the requested public API and no image API expansion.
- The Gradle task validates exact values and fails before the ABI `Exec` task.
- The temporary macOS 15 deployment-target change was reverted; `swift-java`
  `0.2.0` supports the package's existing macOS 14 declaration.
- The Gradle scaffold is intentionally limited to the root, build logic, one
  core module, the validation task, and arm64 build task.

## Blockers

- The initial Swift build of the compatible `swift-java` pin had not completed,
  so the required XCTest and `byte[]` generation evidence is unavailable.
- This environment has no Gradle launcher/wrapper and no configured Android NDK,
  preventing execution of the required Gradle verification commands.

## Takeover verification (2026-08-26)

The prior blockers are now partially resolved. The scoped implementation was
reviewed and retained, with the following corrections:

- Added the pinned Gradle 8.14.5 wrapper already present in `Android/` to the
  scoped implementation set.
- Aligned `Android/gradle/libs.versions.toml` to the package's exact
  `swift-java` `0.2.0` pin (it incorrectly still stated `0.1.2`).
- Corrected `buildSwiftArm64-v8a` to invoke SwiftPM from the package root
  (`Android`'s parent), and to build the `SeamCarvingAndroidBridge` target.
  `--product` cannot select this library product in this SwiftPM invocation.

Fresh successful evidence:

1. `swift test --filter SeamCarvingAndroidBridgeTests`
   - Passed: `BridgeProbeTests.testEchoPreservesEveryByte`.
   - XCTest summary: 1 test executed, 0 failures.
2. The SwiftJava plugin generated
   `.build/plugins/outputs/android-gradle-library/SeamCarvingAndroidBridge/destination/JExtractSwiftPlugin/src/generated/java/io/github/seamcarving/internal/BridgeProbe.java`.
   Its public surface is exactly `public static byte[] echo(@Unsigned byte[] bytes)`,
   with a private JNI downcall `private static native byte[] $echo(byte[] bytes)`.
   No alternate transport was introduced.
3. With `ANDROID_NDK_HOME` set to
   `/Users/samzhjiang/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d`,
   `./gradlew :seamcarving-android-core:verifySwiftAndroidToolchain --no-daemon`
   passed. It reported Swiftly `1.1.3`, Swift `6.3.3`, the installed
   `swift-6.3.3-RELEASE_android` SDK, and accepted NDK `27.3.13750724`.

ABI build blocker:

- The required
  `./gradlew :seamcarving-android-core:buildSwiftArm64-v8a --no-daemon`
  now enters the package's Swift compilation after the working-directory fix,
  but cannot complete with the supplied SDK configuration. The documented
  direct command
  `swiftly run swift +6.3.3 build --swift-sdk aarch64-unknown-linux-android28 --target SeamCarvingAndroidBridge --build-system native --jobs 4`
  fails while compiling `SwiftJavaJNICore` and `SeamCarvingCore` with:
  `could not find module 'Swift' for target 'aarch64-unknown-linux-android'; found: x86_64-unknown-linux-android`.
- Investigation found the supplied SDK's `ndk-sysroot/usr/include` symlink
  points at a different stale NDK location under
  `/Users/samzhjiang/.swiftpm/.../android-ndk-r27d/.../darwin-x86_64`, not the
  provided NDK path. Swift.org's Android SDK instructions require rerunning
  the bundle's `scripts/setup-android-sdk.sh` to recreate that sysroot; doing
  so would edit the SDK outside this task's isolated worktree and was therefore
  not performed.

Final status remains blocked and no commit was created: the mandated arm64
ABI build has no passing evidence. The bridge XCTest, Java `byte[]` proof, and
toolchain verification do pass.

## Final verification after authorized SDK repair (2026-08-26)

The Android SDK setup script was subsequently authorized and run outside this
worktree to re-link `ndk-sysroot` to the required NDK. With
`ANDROID_NDK_HOME` set to the required `android-ndk-r27d` location:

1. `./gradlew :seamcarving-android-core:buildSwiftArm64-v8a --no-daemon`
   passed. The dependent toolchain verification again reported Swiftly 1.1.3,
   Swift 6.3.3, `swift-6.3.3-RELEASE_android`, and NDK 27.3.13750724. SwiftPM
   finished with `Build of target: 'SeamCarvingAndroidBridge' complete!`.
2. The repaired Android compilation exposed one platform-only Core issue:
   Android's Foundation resolves `pow` only as `Double`, while
   `LinearSRGB` works in `Float`. `Energy.swift` now uses `powf` for both
   transfer-function calls; this is the minimal Float-preserving fix and does
   not change the bridge transport.
3. `swift test --filter SeamCarvingAndroidBridgeTests` passed: 1 test, 0
   failures. `BridgeProbe.java` was regenerated and confirms
   `public static byte[] echo(@Unsigned byte[] bytes)`.
4. `swift test --filter BackwardEnergyTests` passed: 7 tests, 0 failures,
   covering the Core code affected by the Android Float-math correction.

All Task 1 acceptance checks now have passing evidence. The staged commit
contains only the Android Gradle scaffold/wrapper, Swift bridge and test,
pinned SwiftPM resolution, the Android compilation portability fix, and this
task report.
