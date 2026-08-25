# Android Gradle Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish SeamCarving as Android Gradle dependencies with a CPU-backed RGBA core API, Bitmap adapter, and optional ML Kit face-protection adapter.

**Architecture:** Keep `SeamCarvingCore` platform-neutral. Build one Swift dynamic `SeamCarvingAndroidBridge` library for each Android ABI, hide generated JNI classes behind Kotlin APIs, and split Gradle artifacts by capability.

**Tech Stack:** Swift 6.3.3 open-source toolchain, Swift Android SDK 6.3.3, Android NDK r27d, SwiftPM, swift-java JNI mode, AGP, Kotlin coroutines, Maven Publish, ML Kit.

**Spec:** `docs/superpowers/specs/2026-08-25-android-gradle-library-design.md`

## Global Constraints

- Pin every toolchain, SDK, NDK, Gradle, Kotlin, and swift-java version; consumers install none of them.
- `minSdk = 28`; release ABIs are `arm64-v8a`, `armeabi-v7a`, and `x86_64`.
- Android native code depends on `SeamCarvingCore` only and is CPU-only.
- Kotlin is the only stable external API. Generated Java/JNI symbols are internal.
- Pixels are upright, origin-zero, straight-alpha, row-major RGBA8.
- Only `seamcarving-android-core` packages Swift/C++ runtime `.so` files.
- The default facade excludes ML Kit.

## File Structure

| Path | Responsibility |
| --- | --- |
| `Package.swift` | Dynamic bridge product plus pinned swift-java dependency. |
| `Sources/SeamCarvingAndroidBridge/` | JNI-safe Swift operations forwarding to Core. |
| `Android/build-logic/` | Pinned toolchain, ABI packaging, Maven conventions. |
| `Android/seamcarving-android-core/` | Kotlin RGBA/mask API and native AAR. |
| `Android/seamcarving-android-bitmap/` | Bitmap conversion; no native libraries. |
| `Android/seamcarving-android-mlkit/` | Optional face detection to mask adapter. |
| `Android/seamcarving-android/` | Default core+Bitmap facade. |
| `Android/sample/` | Maven-only consumer verification. |
| `.github/workflows/android-library.yml` | ABI, device, consumer, and release gates. |

### Task 1: Establish a pinned Android Swift bridge build

**Files:**
- Create: `Android/settings.gradle.kts`, `Android/build.gradle.kts`, `Android/gradle/libs.versions.toml`, `Android/gradle.properties`
- Create: `Android/build-logic/settings.gradle.kts`, `Android/build-logic/build.gradle.kts`, `Android/build-logic/src/main/kotlin/com.seamcarving.android.toolchain.gradle.kts`
- Modify: `Package.swift`
- Create: `Sources/SeamCarvingAndroidBridge/BridgeProbe.swift`
- Create: `Tests/SeamCarvingAndroidBridgeTests/BridgeProbeTests.swift`

**Interfaces:**
- Produces: dynamic `SeamCarvingAndroidBridge` and Gradle task `verifySwiftAndroidToolchain`.
- Consumes: `SeamCarvingCore` only.

- [ ] **Step 1: Write the failing bridge test**

```swift
final class BridgeProbeTests: XCTestCase {
    func testEchoPreservesEveryByte() {
        XCTAssertEqual(BridgeProbe.echo([0, 1, 127, 255]), [0, 1, 127, 255])
    }
}
```

- [ ] **Step 2: Verify the failure**

Run: `swift test --filter SeamCarvingAndroidBridgeTests`

Expected: FAIL because the bridge target is missing.

- [ ] **Step 3: Add the minimal dynamic bridge**

Add a dynamic product and target that depends on `SeamCarvingCore` and pinned `SwiftJava`, with `JExtractSwiftPlugin`. Implement:

```swift
public enum BridgeProbe {
    public static func echo(_ bytes: [UInt8]) -> [UInt8] { bytes }
}
```

- [ ] **Step 4: Implement exact toolchain validation**

The convention plugin must check these values before invoking Swift:

```kotlin
val requiredSwift = "6.3.3"
val requiredSwiftSdk = "swift-6.3.3-RELEASE_android"
val requiredNdk = "27.3.13750724"
```

It runs `swiftly run swift +6.3.3 --version`, `swift sdk list`, and inspects `ANDROID_NDK_HOME/source.properties`. It must never download an unpinned toolchain.

- [ ] **Step 5: Prove JNI generation handles binary input**

Run: `swift test --filter SeamCarvingAndroidBridgeTests && ./gradlew :seamcarving-android-core:verifySwiftAndroidToolchain :seamcarving-android-core:buildSwiftArm64-v8a`

Expected: PASS and generated Java accepts/returns `byte[]`. If it cannot, stop and revise the bridge contract before image work.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Package.resolved Sources/SeamCarvingAndroidBridge Tests/SeamCarvingAndroidBridgeTests Android
git commit -m "build: scaffold pinned Android Swift bridge"
```

### Task 2: Assemble the all-ABI core AAR

**Files:**
- Create: `Android/build-logic/src/main/kotlin/com.seamcarving.android.native-library.gradle.kts`
- Create: `Android/seamcarving-android-core/build.gradle.kts`, `src/main/AndroidManifest.xml`
- Create: `Android/seamcarving-android-core/src/test/kotlin/io/github/seamcarving/NativePackagingTest.kt`

**Interfaces:**
- Produces: core AAR with bridge, `libc++_shared.so`, and required Swift runtime files under each `jni/<abi>/`.
- Consumes: Task 1 dynamic library.

- [ ] **Step 1: Write the failing AAR inspection test**

```kotlin
@Test fun releaseAarContainsAllRequiredAbis() {
  val entries = ZipFile(releaseAar).entries().asSequence().map { it.name }.toSet()
  listOf("arm64-v8a", "armeabi-v7a", "x86_64").forEach { abi ->
    assertTrue("jni/$abi/libSeamCarvingAndroidBridge.so" in entries)
    assertTrue("jni/$abi/libswiftCore.so" in entries)
  }
}
```

- [ ] **Step 2: Verify the failure**

Run: `./gradlew :seamcarving-android-core:testReleaseUnitTest`

Expected: FAIL because no AAR exists.

- [ ] **Step 3: Build and copy every ABI**

Map ABI names exactly:

```kotlin
val triples = mapOf(
 "arm64-v8a" to "aarch64-unknown-linux-android28",
 "armeabi-v7a" to "armv7-unknown-linux-android28",
 "x86_64" to "x86_64-unknown-linux-android28",
)
```

Each build invokes `swiftly run swift +6.3.3 build --swift-sdk <triple> --build-system native -c release --product SeamCarvingAndroidBridge`. Copy bridge, NDK `libc++_shared.so`, and pinned Swift runtime libraries only to `build/generated/jniLibs/<abi>`; attach it to core's `jniLibs` source set.

- [ ] **Step 4: Verify packaging**

Run: `./gradlew :seamcarving-android-core:assembleRelease :seamcarving-android-core:testReleaseUnitTest`

Expected: PASS with all three ABI directories.

- [ ] **Step 5: Commit**

```bash
git add Android/build-logic Android/seamcarving-android-core
git commit -m "build: package Android core native libraries"
```

### Task 3: Implement the stable RGBA API

**Files:**
- Create: `Sources/SeamCarvingAndroidBridge/AndroidResizeBridge.swift`
- Create: `Tests/SeamCarvingAndroidBridgeTests/AndroidResizeBridgeTests.swift`
- Create: `Android/seamcarving-android-core/src/main/kotlin/io/github/seamcarving/{RgbaImage,Mask,ResizeRequest,SeamCarver,SeamCarvingException}.kt`
- Create: `Android/seamcarving-android-core/src/test/kotlin/io/github/seamcarving/RgbaImageTest.kt`
- Create: `Android/seamcarving-android-core/src/androidTest/kotlin/io/github/seamcarving/ResizeParityTest.kt`

**Interfaces:**
- Produces: `data class RgbaImage(val width: Int, val height: Int, val bytes: ByteArray)`, `data class Mask(...)`, and `suspend fun SeamCarver.resize(request: ResizeRequest): RgbaImage`.
- Consumes: native `resizeRGBA` and Core `RGBA8Image`.

- [ ] **Step 1: Write failing validation and resize tests**

```kotlin
@Test fun rgbaRejectsWrongByteCount() {
  assertFailsWith<IllegalArgumentException> { RgbaImage(2, 2, ByteArray(15)) }
}
@Test fun resizeReturnsTargetSize() = runTest {
  val output = SeamCarver().resize(ResizeRequest(RgbaImage(2, 2, fixture), 1, 2))
  assertEquals(1, output.width); assertEquals(2, output.height)
}
```

- [ ] **Step 2: Verify failure**

Run: `./gradlew :seamcarving-android-core:testDebugUnitTest`

Expected: FAIL because public types are missing.

- [ ] **Step 3: Implement Core forwarding and error mapping**

Construct Core `RGBA8Image` and `PixelSize` in Swift; return width, height, and RGBA bytes. Kotlin validates count with `Math.multiplyExact(Math.multiplyExact(width, height), 4)` before JNI, keeps generated classes `internal`, and maps native errors to `SeamCarvingException`. Map masks only after both dimensions equal the source image.

- [ ] **Step 4: Verify host and Android parity**

Run: `swift test --filter SeamCarvingAndroidBridgeTests && ./gradlew :seamcarving-android-core:connectedDebugAndroidTest`

Expected: PASS; canonical Android output bytes equal Core fixture bytes.

- [ ] **Step 5: Commit**

```bash
git add Sources/SeamCarvingAndroidBridge Tests/SeamCarvingAndroidBridgeTests Android/seamcarving-android-core
git commit -m "feat: expose Android RGBA seam carving API"
```

### Task 4: Add progress and cancellation

**Files:**
- Modify: `Sources/SeamCarvingAndroidBridge/AndroidResizeBridge.swift`
- Modify: `Android/seamcarving-android-core/src/main/kotlin/io/github/seamcarving/{ResizeRequest,SeamCarver}.kt`
- Create: `Android/seamcarving-android-core/src/androidTest/kotlin/io/github/seamcarving/CancellationAndProgressTest.kt`

**Interfaces:**
- Produces: `fun SeamCarver.resizeWithProgress(request: ResizeRequest): Flow<ResizeProgress>`.
- Consumes: Core progress callback and cooperative cancellation.

- [ ] **Step 1: Write the failing cancellation test**

```kotlin
@Test fun cancellingCollectionCancelsResize() = runTest {
  val job = launch { carver.resizeWithProgress(largeRequest).collect { cancel() } }
  job.join(); assertTrue(job.isCancelled)
}
```

- [ ] **Step 2: Verify failure**

Run: `./gradlew :seamcarving-android-core:connectedDebugAndroidTest`

Expected: FAIL because the Flow API is missing.

- [ ] **Step 3: Implement callback and cancellation propagation**

Bridge `ResizeOptions.progress` into a Kotlin callback. Check Kotlin cancellation before every progress delivery; translate it to Swift task cancellation. Do not call Kotlin while a Swift lock is held.

- [ ] **Step 4: Verify**

Run: `./gradlew :seamcarving-android-core:connectedDebugAndroidTest`

Expected: PASS without a native crash or callback after cancellation.

- [ ] **Step 5: Commit**

```bash
git add Sources/SeamCarvingAndroidBridge Android/seamcarving-android-core
git commit -m "feat: add Android progress and cancellation"
```

### Task 5: Add the Bitmap-only adapter

**Files:**
- Create: `Android/seamcarving-android-bitmap/build.gradle.kts`
- Create: `Android/seamcarving-android-bitmap/src/main/kotlin/io/github/seamcarving/bitmap/BitmapSeamCarver.kt`
- Create: `Android/seamcarving-android-bitmap/src/androidTest/kotlin/io/github/seamcarving/bitmap/BitmapConversionTest.kt`

**Interfaces:**
- Produces: `fun Bitmap.toRgbaImage(): RgbaImage` and `suspend fun Bitmap.seamCarveTo(width: Int, height: Int): Bitmap`.
- Consumes: Task 3 APIs; contains no native files.

- [ ] **Step 1: Write the failing channel-order test**

```kotlin
@Test fun bitmapRoundTripPreservesRgba() {
  val bitmap = Bitmap.createBitmap(intArrayOf(0x80402010.toInt()), 1, 1, Bitmap.Config.ARGB_8888)
  assertContentEquals(byteArrayOf(0x40, 0x20, 0x10, 0x80.toByte()), bitmap.toRgbaImage().bytes)
}
```

- [ ] **Step 2: Verify failure**

Run: `./gradlew :seamcarving-android-bitmap:connectedDebugAndroidTest`

Expected: FAIL because conversion is absent.

- [ ] **Step 3: Implement explicit conversion**

Use `getPixels()` and `setPixels()`, extracting `r = pixel ushr 16`, `g = pixel ushr 8`, `b = pixel`, and `a = pixel ushr 24`. Rebuild as `(a shl 24) or (r shl 16) or (g shl 8) or b`.

- [ ] **Step 4: Verify conversion and artifact separation**

Run: `./gradlew :seamcarving-android-bitmap:connectedDebugAndroidTest :seamcarving-android-bitmap:assembleRelease`

Expected: PASS; bitmap AAR contains no `jni/` entries.

- [ ] **Step 5: Commit**

```bash
git add Android/seamcarving-android-bitmap
git commit -m "feat: add Android Bitmap adapter"
```

### Task 6: Add optional ML Kit protection masks

**Files:**
- Create: `Android/seamcarving-android-mlkit/build.gradle.kts`
- Create: `Android/seamcarving-android-mlkit/src/main/kotlin/io/github/seamcarving/mlkit/FaceProtectionMask.kt`
- Create: `Android/seamcarving-android-mlkit/src/test/kotlin/io/github/seamcarving/mlkit/FaceProtectionMaskTest.kt`
- Create: `Android/seamcarving-android-mlkit/src/androidTest/kotlin/io/github/seamcarving/mlkit/MlKitFaceDetectorTest.kt`

**Interfaces:**
- Produces: `suspend fun Bitmap.detectFaceProtectionMask(): Mask`.
- Consumes: Bitmap adapter and ML Kit only; does not modify Swift.

- [ ] **Step 1: Write the failing rasterization test**

```kotlin
@Test fun faceRectangleCreatesBoundedProtection() {
  val mask = FaceProtectionMask.rasterize(8, 6, listOf(Rect(2, 1, 6, 5)))
  assertEquals(0, mask[0, 0]); assertTrue(mask[3, 3] > 0)
}
```

- [ ] **Step 2: Verify failure**

Run: `./gradlew :seamcarving-android-mlkit:testDebugUnitTest`

Expected: FAIL because module/rasterizer is missing.

- [ ] **Step 3: Implement Kotlin-only detector and rasterizer**

Convert ML Kit bounding boxes and optional landmark padding into clamped byte masks. Return all-zero mask for no faces; preserve the detector exception as the cause when throwing `SeamCarvingException`.

- [ ] **Step 4: Verify**

Run: `./gradlew :seamcarving-android-mlkit:testDebugUnitTest :seamcarving-android-mlkit:connectedDebugAndroidTest`

Expected: PASS for face and no-face fixtures.

- [ ] **Step 5: Commit**

```bash
git add Android/seamcarving-android-mlkit
git commit -m "feat: add optional Android ML Kit masks"
```

### Task 7: Publish facade artifacts and verify a clean consumer

**Files:**
- Create: `Android/seamcarving-android/build.gradle.kts`
- Create: `Android/build-logic/src/main/kotlin/com.seamcarving.android.publish.gradle.kts`
- Create: `Android/sample/build.gradle.kts`
- Create: `Android/sample/src/main/kotlin/io/github/seamcarving/sample/MainActivity.kt`
- Create: `Android/sample/src/androidTest/kotlin/io/github/seamcarving/sample/MavenConsumerTest.kt`

**Interfaces:**
- Produces: local Maven coordinates for core, bitmap, ML Kit, and facade; facade depends on core+bitmap and excludes ML Kit.
- Consumes: Tasks 2–6.

- [ ] **Step 1: Write the failing publication-graph test**

```kotlin
@Test fun facadePomIncludesBitmapButExcludesMlKit() {
  val pom = publicationPom.readText()
  assertTrue(pom.contains("seamcarving-android-bitmap"))
  assertFalse(pom.contains("face-detection"))
}
```

- [ ] **Step 2: Verify failure**

Run: `./gradlew :seamcarving-android:testReleaseUnitTest`

Expected: FAIL because no POM exists.

- [ ] **Step 3: Implement Maven Publish**

Publish sources JARs and POMs from all four artifacts using root `VERSION_NAME`. Create `publishAllPublicationsToBuildRepository` that writes to `Android/build/local-maven`; reserve signing and Sonatype credentials for remote release tasks. Sample dependencies must use only `io.github.seamcarving:seamcarving-android:$VERSION_NAME`, never Gradle project dependencies.

- [ ] **Step 4: Verify Maven consumption**

Run: `./gradlew publishAllPublicationsToBuildRepository :sample:connectedDebugAndroidTest`

Expected: PASS without local Swift/NDK configuration in sample.

- [ ] **Step 5: Commit**

```bash
git add Android/build-logic Android/seamcarving-android Android/sample
git commit -m "feat: publish Android Gradle artifacts"
```

### Task 8: Add CI and documentation

**Files:**
- Create: `.github/workflows/android-library.yml`
- Modify: `README.md`, `README.zh-CN.md`, `docs/architecture.md`, `docs/architecture/platform-targets.md`, `docs/capability-matrix.md`

**Interfaces:**
- Produces: PR ABI/device/consumer gate and tag-only Maven Central release gate.

- [ ] **Step 1: Write the failing CI assertion**

```bash
rg -F 'aarch64-unknown-linux-android28' .github/workflows/android-library.yml
rg -F ':sample:connectedDebugAndroidTest' .github/workflows/android-library.yml
```

- [ ] **Step 2: Verify failure**

Run: `test -f .github/workflows/android-library.yml`

Expected: FAIL because workflow is absent.

- [ ] **Step 3: Implement CI and docs**

PR jobs install pinned Swift, Android SDK, NDK r27d, JDK 25, and emulator; run Tasks 1–7 gates. Tag-only job requires protected Maven credentials/signing and uploads failure artifacts. Documentation must distinguish core/Bitmap support, optional ML Kit, and Apple-only capabilities.

- [ ] **Step 4: Verify syntax and docs**

Run: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/android-library.yml')" && rg -n 'seamcarving-android(-mlkit)?' README.md README.zh-CN.md docs/architecture.md docs/capability-matrix.md`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/android-library.yml README.md README.zh-CN.md docs
git commit -m "ci: verify and document Android Gradle library"
```

## Plan Self-Review

- **Spec coverage:** Tasks 1–2 pin and package the native core; Tasks 3–4 add RGBA/masks/progress/cancellation; Task 5 adds Bitmap; Task 6 adds optional ML Kit; Task 7 proves Maven integration; Task 8 provides CI and documentation.
- **Placeholder scan:** No deferred work items are present. Consumer Maven coordinates are versioned by the one root `VERSION_NAME`.
- **Type consistency:** Core introduces `RgbaImage`, `Mask`, `ResizeRequest`, `ResizeProgress`, `SeamCarver`, and `SeamCarvingException` before adapters consume them. Runtime libraries remain exclusively in core.

