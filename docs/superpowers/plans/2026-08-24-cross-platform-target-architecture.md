# Cross-Platform Target Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Apple 聚合 target 拆成按能力划分的运行时与图像 adapter target，同时保持算法核心可独立构建，为 Wasm、Android、Windows adapter 提供稳定边界。

**Architecture:** `SeamCarvingCore` 是唯一的算法与像素模型层。Apple 后端选择移动到没有系统图像类型的 `SeamCarvingAppleRuntime`；CGImage/Core Image、Core Video、UIKit、AppKit 各自放入独立 adapter target。未来平台只能依赖 Core，并在自己的 bridge 中完成宿主图像对象与 `RGBA8Image` 的转换。

**Tech Stack:** Swift 6、Swift Package Manager、CoreGraphics、CoreImage、CoreVideo、UIKit、AppKit、Accelerate、Metal、XCTest。

**Spec:** `docs/architecture/platform-targets.md`

## Global Constraints

- 这是 v2.0 的模块重组；`AppleSeamCarver`、`AppleSeamCarverConfiguration` 和 CGImage public API 的函数签名保持不变。
- `SeamCarvingCore` 不得导入 Apple 图形/媒体/计算框架，也不得包含条件编译。
- 禁止以 `#if os(...)` 在一个 target 内同时维护 UIKit 与 AppKit API；分别创建 target。
- 当前正式功能支持仍为 iOS 17+、macOS 14+；Wasm、Android、Windows 在 adapter 和 CI 落地前不得写为“已支持”。
- 所有移动先以测试保护，再删除原文件；每项 task 完成后运行列出的最小测试。

---

## 完成态文件结构

| 路径 | 责任 |
| --- | --- |
| `Sources/SeamCarvingAppleRuntime/AppleSeamCarver.swift` | RGBA8 runtime API、配置和 backend 注入入口 |
| `Sources/SeamCarvingAppleRuntime/BackendFactory.swift` | Metal → Accelerate → CPU capability 选择 |
| `Sources/SeamCarvingAppleImaging/CGImageBridge.swift` | CGImage 与 RGBA8 转换及方向处理 |
| `Sources/SeamCarvingAppleImaging/AppleSeamCarver+CGImage.swift` | CGImage public overload |
| `Sources/SeamCarvingAppleImaging/AppleSeamCarver+CIImage.swift` | CIImage public overload |
| `Sources/SeamCarvingAppleImaging/CIImageBridge.swift` | CIImage 转换 |
| `Sources/SeamCarvingAppleImaging/PreScale.swift` | Core Image Lanczos pre-scale |
| `Sources/SeamCarvingCoreVideo/*` | CVPixelBuffer bridge 与 overload |
| `Sources/SeamCarvingUIKit/*` | UIImage bridge、orientation 与 overload |
| `Sources/SeamCarvingAppKit/*` | NSImage bridge 与 overload |
| `Sources/SeamCarvingApple/Exports.swift` | v2 compatibility re-export，仅导出 Runtime 与 Imaging |

## Task 1: 固化 Apple deployment floor 语义并让 Core portability gate 可验证

**Files:**
- Create: `docs/architecture/platform-targets.md`
- Create: `.github/workflows/core-portability.yml`
- Modify: `Package.swift:5-7`

**Produces:** 跨平台边界文档、正确的 Apple deployment floor 说明与 Core-only CI 门禁。

- [ ] **Step 1: 保留 package 级 Apple deployment floor，并明确其语义**

在 `Package.swift` 保留：

```swift
platforms: [.iOS(.v17), .macOS(.v14)],
```

该声明定义 Apple 端 API 的最低 deployment floor，不是 Apple-exclusive host restriction。Windows/Linux/Wasm 的宿主可用性仍由实际 toolchain 对 `SeamCarvingCore` 的解析、构建与测试结果决定，而不是由这行声明单独决定。

- [ ] **Step 2: 添加 Core portability CI**

创建 `.github/workflows/core-portability.yml`：

```yaml
name: Core portability
on: [push, pull_request]
jobs:
  core:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-latest, ubuntu-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: swift-actions/setup-swift@v2
        with:
          swift-version: '6.0'
      - run: bash Scripts/check-target-boundaries.sh
      - run: swift build --target SeamCarvingCore
      - run: swift test --filter SeamCarvingCoreTests
```

若 Windows runner 的 Swift 安装机制不同，使用当期官方等价安装步骤，但不得跳过 Windows job。

- [ ] **Step 3: 本机验证**

Run: `swift build --target SeamCarvingCore && swift test --filter SeamCarvingCoreTests`

Expected: Apple deployment floors 保持不变；Core portability gate 在本机通过，并继续作为 macOS/Linux/Windows toolchain 支持的实际判定。

- [ ] **Step 4: 提交**

```bash
git add Package.swift docs/architecture/platform-targets.md .github/workflows/core-portability.yml
git commit -m "docs: define cross-platform target boundaries"
```

## Task 2: 提取无图像框架的 Apple runtime

**Files:**
- Create: `Sources/SeamCarvingAppleRuntime/AppleSeamCarver.swift`
- Create: `Sources/SeamCarvingAppleRuntime/BackendFactory.swift`
- Create: `Tests/SeamCarvingAppleRuntimeTests/BackendSelectionTests.swift`
- Modify: `Package.swift`
- Delete: `Sources/SeamCarvingApple/BackendFactory.swift`
- Modify then delete: `Sources/SeamCarvingApple/AppleSeamCarver.swift`
- Delete: `Tests/SeamCarvingAppleTests/BackendSelectionTests.swift`

**Consumes:** `SeamCarvingCore` backend SPI、Accelerate、Metal。

**Produces:** 无 CGImage/CIImage/CVPixelBuffer/UIKit/AppKit import 的 Apple backend runtime。

- [ ] **Step 1: 写失败测试**

保留现有 fallback 测试，并新增：

```swift
func testRuntimeResizeUsesInjectedCPUBackend() async throws {
    let image = try RGBA8Image(width: 2, height: 2, pixels: [
        0, 0, 0, 255, 255, 0, 0, 255,
        0, 255, 0, 255, 0, 0, 255, 255,
    ])
    let carver = try AppleSeamCarver(configuration: .init(backend: .cpu, deterministic: true))
    let output = try await carver.resize(image, toPixelSize: try PixelSize(width: 1, height: 2))
    XCTAssertEqual((output.width, output.height), (1, 2))
}
```

- [ ] **Step 2: 确认测试失败**

Run: `swift test --filter SeamCarvingAppleRuntimeTests`

Expected: FAIL，因为 target 和 RGBA8 API 尚不存在。

- [ ] **Step 3: 实现稳定像素入口**

定义：

```swift
public struct AppleSeamCarver: Sendable {
    public init(configuration: AppleSeamCarverConfiguration = .init()) throws
    public func resize(
        _ image: RGBA8Image,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> RGBA8Image
    public func findSeam(
        in image: RGBA8Image,
        orientation: SeamOrientation,
        options: ResizeOptions = .init()
    ) async throws -> SeamPath
}
```

把 `AppleSeamCarverConfiguration`、`BackendFactory` 和测试注入 initializer 一起移动。该 target 的 import 只能为 `Foundation`、`@_spi(Backend) SeamCarvingCore`、`SeamCarvingAccelerate`、`SeamCarvingMetal`；不得有 `#if`。

- [ ] **Step 4: 声明 target**

```swift
.library(name: "SeamCarvingAppleRuntime", targets: ["SeamCarvingAppleRuntime"]),
.target(
    name: "SeamCarvingAppleRuntime",
    dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal"]
),
.testTarget(
    name: "SeamCarvingAppleRuntimeTests",
    dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime"]
),
```

- [ ] **Step 5: 验证并提交**

Run: `swift test --filter SeamCarvingAppleRuntimeTests && swift build --target SeamCarvingCore`

Expected: Metal → Accelerate → CPU fallback 不变；Core 仍独立构建。

```bash
git add Package.swift Sources/SeamCarvingAppleRuntime Tests/SeamCarvingAppleRuntimeTests Sources/SeamCarvingApple Tests/SeamCarvingAppleTests
git commit -m "refactor: extract Apple backend runtime"
```

## Task 3: 提取 CoreGraphics/Core Image adapter

**Files:**
- Create: `Sources/SeamCarvingAppleImaging/CGImageBridge.swift`
- Create: `Sources/SeamCarvingAppleImaging/CIImageBridge.swift`
- Create: `Sources/SeamCarvingAppleImaging/PreScale.swift`
- Create: `Sources/SeamCarvingAppleImaging/AppleSeamCarver+CGImage.swift`
- Create: `Sources/SeamCarvingAppleImaging/AppleSeamCarver+CIImage.swift`
- Create: `Tests/SeamCarvingAppleImagingTests/AppleImagingBridgeTests.swift`
- Modify: `Package.swift`
- Delete: `Sources/SeamCarvingApple/CGImageBridge.swift`, `CIImageBridge.swift`, `PreScale.swift`

**Produces:** 一个含 CGImage/CIImage 适配、但不含 UIKit/AppKit/CoreVideo 条件分支的 Imaging target。

- [ ] **Step 1: 迁移失败测试**

将 `AppleBridgeTests` 中以下测试移至新 test target：CGImage round-trip、premultiplied alpha、orientation、16-bit 拒绝、灰度、BGRA、padded bytes-per-row、Display P3、CGImage resize、Lanczos pre-scale、CIImage resize。保留原断言。

新增：

```swift
func testCGImageOverloadReachesTargetDimensions() async throws {
    let image = try Self.makeCGImage(width: 4, height: 3, pixels: Self.gradientPixels(width: 4, height: 3), alphaInfo: .last)
    let result = try await AppleSeamCarver(configuration: .init(backend: .cpu, deterministic: true))
        .resize(image, toPixelSize: try PixelSize(width: 2, height: 2))
    XCTAssertEqual((result.width, result.height), (2, 2))
}
```

- [ ] **Step 2: 确认测试失败**

Run: `swift test --filter SeamCarvingAppleImagingTests`

Expected: FAIL，因为 adapter target 尚未存在。

- [ ] **Step 3: 实现 overload 与 pre-scale**

CGImage extension 固定为 `decode → PreScalePlanner.plan → runtime RGBA8 resize/findSeam → encode`。CIImage extension 固定为 `CIImageBridge.decode → runtime resize → CIImageBridge.encode`。

`PreScale.swift` 可直接 import CoreImage，且不再包含 `#if canImport(CoreImage)` fallback；它是明确的 capability target。缺少该 target 的调用方使用 runtime RGBA8 API，或提供其平台自己的 resampler。

- [ ] **Step 4: 声明 target 并验证**

```swift
.library(name: "SeamCarvingAppleImaging", targets: ["SeamCarvingAppleImaging"]),
.target(name: "SeamCarvingAppleImaging", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime"]),
.testTarget(name: "SeamCarvingAppleImagingTests", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"]),
```

Run: `swift test --filter SeamCarvingAppleImagingTests`

Expected: 所有像素格式、方向、pre-scale 和 CIImage 测试通过。

- [ ] **Step 5: 提交**

```bash
git add Package.swift Sources/SeamCarvingAppleImaging Tests/SeamCarvingAppleImagingTests Sources/SeamCarvingApple Tests/SeamCarvingAppleTests
git commit -m "refactor: isolate Apple imaging adapters"
```

## Task 4: 提取 CoreVideo、UIKit、AppKit adapter

**Files:**
- Create: `Sources/SeamCarvingCoreVideo/CVPixelBufferBridge.swift`, `AppleSeamCarver+CVPixelBuffer.swift`
- Create: `Sources/SeamCarvingUIKit/UIImageBridge.swift`, `AppleSeamCarver+UIImage.swift`
- Create: `Sources/SeamCarvingAppKit/NSImageBridge.swift`, `AppleSeamCarver+NSImage.swift`
- Create: `Tests/SeamCarvingCoreVideoTests/CVPixelBufferBridgeTests.swift`
- Create: `Tests/SeamCarvingUIKitTests/UIImageBridgeTests.swift`
- Create: `Tests/SeamCarvingAppKitTests/NSImageBridgeTests.swift`
- Modify: `Package.swift`
- Delete: `Sources/SeamCarvingApple/CVPixelBufferBridge.swift`, `PlatformImageBridge.swift`

**Produces:** 三个互不包含对方 framework 的 platform adapter。

- [ ] **Step 1: 写三个失败测试**

CoreVideo：从原 `testCVPixelBufferRoundTrip` 移动 BGRA/alpha 断言，并新增 resize 尺寸断言：

```swift
XCTAssertEqual(CVPixelBufferGetWidth(result), 2)
XCTAssertEqual(CVPixelBufferGetHeight(result), 2)
```

UIKit：用 `UIImage(cgImage:scale:orientation:)` 创建 `.right`、`scale: 2` 的图像，resize 后断言：

```swift
XCTAssertEqual(result.imageOrientation, .up)
XCTAssertEqual(result.scale, 2)
XCTAssertEqual(Int(result.size.width * result.scale), 2)
XCTAssertEqual(Int(result.size.height * result.scale), 2)
```

AppKit：用 `NSImage(cgImage:size:)` 创建 4×3 图像，resize 后断言：

```swift
let outputCG = try XCTUnwrap(result.cgImage(forProposedRect: nil, context: nil, hints: nil))
XCTAssertEqual(outputCG.width, 2)
XCTAssertEqual(outputCG.height, 2)
```

- [ ] **Step 2: 确认测试失败**

Run: `swift test --filter SeamCarvingCoreVideoTests && swift test --filter SeamCarvingAppKitTests`

Expected: FAIL，因为 target 尚未存在。

Run: `xcodebuild test -scheme SeamCarvingSwift-Package -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SeamCarvingUIKitTests`

Expected: FAIL；若该 simulator 名称不存在，先用 `xcrun simctl list devices available` 选择已安装 iPhone runtime，仍必须在 iOS Simulator 测试。

- [ ] **Step 3: 实现每个 adapter**

- CoreVideo：保留当前仅接受 BGRA/RGBA、lock/unlock 和 row stride 处理；extension 只做 `decode → runtime resize → encode`。
- UIKit：`UIImageBridge` 负责 `UIImage.Orientation → CGImagePropertyOrientation`、保留 scale，并始终 encode 为 `.up`；不得 import AppKit 或出现 Catalyst 条件。
- AppKit：`NSImageBridge` 用 `cgImage(forProposedRect:context:hints:)` 获取真实 raster；不得 import UIKit 或出现 UIKit 条件。

- [ ] **Step 4: 声明 target**

```swift
.library(name: "SeamCarvingCoreVideo", targets: ["SeamCarvingCoreVideo"]),
.target(name: "SeamCarvingCoreVideo", dependencies: ["SeamCarvingCore", "SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"]),
.library(name: "SeamCarvingUIKit", targets: ["SeamCarvingUIKit"]),
.target(name: "SeamCarvingUIKit", dependencies: ["SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"]),
.library(name: "SeamCarvingAppKit", targets: ["SeamCarvingAppKit"]),
.target(name: "SeamCarvingAppKit", dependencies: ["SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"]),
```

为每个 target 添加对应 XCTest target。

- [ ] **Step 5: 验证并提交**

Run: `swift test --filter SeamCarvingCoreVideoTests && swift test --filter SeamCarvingAppKitTests`

Expected: CoreVideo 的 BGRA/尺寸及 AppKit 的真实 raster 尺寸均通过。

Run: 使用 Step 2 的 iOS simulator `xcodebuild test` 命令。

Expected: UIKit orientation、scale、目标尺寸均通过。

```bash
git add Package.swift Sources/SeamCarvingCoreVideo Sources/SeamCarvingUIKit Sources/SeamCarvingAppKit Tests/SeamCarvingCoreVideoTests Tests/SeamCarvingUIKitTests Tests/SeamCarvingAppKitTests Sources/SeamCarvingApple
git commit -m "refactor: split Apple platform image adapters"
```

## Task 5: 完成 v2 compatibility facade 并迁移内部消费者

**Files:**
- Create: `Sources/SeamCarvingApple/Exports.swift`
- Modify: `Package.swift`
- Modify: `Sources/SeamCarvingVision/FaceAwareSeamCarver.swift`
- Modify: `Sources/SeamCarvingCLI/CLIImageIO.swift`, `CLIProcessor.swift`, `CLIDebugArtifacts.swift`
- Modify: `Sources/SeamCarvingBenchmark/BenchmarkRunner.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/AppModel.swift`, `ImageCanvasView.swift`
- Modify: `README.md`, `README.zh-CN.md`, `docs/architecture.md`, `docs/capability-matrix.md`, `Sources/SeamCarvingApple/SeamCarvingApple.docc/Backends.md`

**Produces:** 每个 consumer 直接依赖所需 adapter；兼容 facade 不再包含 UIKit/AppKit。

- [ ] **Step 1: 写 compatibility export**

`Sources/SeamCarvingApple/Exports.swift`：

```swift
@_exported import SeamCarvingAppleRuntime
@_exported import SeamCarvingAppleImaging
```

原 target dependencies 改为：

```swift
.target(name: "SeamCarvingApple", dependencies: ["SeamCarvingAppleRuntime", "SeamCarvingAppleImaging"])
```

- [ ] **Step 2: 迁移直接依赖**

| Consumer | 直接依赖 |
| --- | --- |
| `SeamCarvingVision` | `SeamCarvingAppleRuntime`, `SeamCarvingAppleImaging` |
| `SeamCarvingCLI` | `SeamCarvingAppleRuntime`, `SeamCarvingAppleImaging`；Vision 继续是可选 Apple 能力 |
| `SeamCarvingBenchmark` | `SeamCarvingAppleImaging` |
| app source target | `SeamCarvingAppleImaging`，实际使用 UIImage/NSImage 时再直接依赖 UIKit/AppKit target |

不要通过 compatibility re-export 隐藏真实依赖。

- [ ] **Step 3: 更新所有文档示例**

加入：

```swift
import SeamCarvingApple        // CGImage API / compatibility facade
import SeamCarvingUIKit        // UIImage overload（iOS/iPadOS/Catalyst）
// 或
import SeamCarvingAppKit       // NSImage overload（macOS）
```

明确 `SeamCarvingCore` 是 Windows/Linux 的“验证构建”，Wasm/Android 是“adapter boundary ready”，不是已交付支持。

- [ ] **Step 4: 验证并提交**

Run: `swift test --parallel`

Expected: Core、Accelerate、Metal、Runtime、Imaging、CoreVideo、AppKit、Vision、CLI、Benchmark 测试通过。

Run: `xcodebuild -scheme SeamCarvingSwift-Package -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: iOS 包构建通过。

```bash
git add Package.swift Sources Tests Apps README.md README.zh-CN.md docs
git commit -m "refactor: adopt capability-based platform modules"
```

## Task 6: 防止依赖回流、发布迁移说明

**Files:**
- Create: `Scripts/check-target-boundaries.sh`
- Create: `docs/migrations/v2-platform-targets.md`
- Modify: `.github/workflows/core-portability.yml`

**Produces:** 可自动执行的边界检查及用户升级路径。

- [ ] **Step 1: 写 target 边界脚本**

`Scripts/check-target-boundaries.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

if grep -R -nE '^(import (Accelerate|Metal|CoreGraphics|CoreImage|CoreVideo|UIKit|AppKit|Vision)|#if (os|canImport)|.*targetEnvironment)' Sources/SeamCarvingCore; then
  echo 'SeamCarvingCore must remain platform-neutral.' >&2
  exit 1
fi
if grep -R -nE 'import AppKit|#if canImport\\(AppKit\\)|targetEnvironment' Sources/SeamCarvingUIKit; then
  echo 'SeamCarvingUIKit must not contain AppKit or Catalyst branches.' >&2
  exit 1
fi
if grep -R -nE 'import UIKit|#if canImport\\(UIKit\\)' Sources/SeamCarvingAppKit; then
  echo 'SeamCarvingAppKit must not contain UIKit branches.' >&2
  exit 1
fi
```

给脚本可执行权限，并确保 Task 1 CI 在 build 前运行它。

- [ ] **Step 2: 写 v2 迁移文档**

创建 import 替换表：

| v1 import/API | v2 操作 |
| --- | --- |
| `import SeamCarvingApple` + CGImage | 无需变化 |
| UIImage overload | 增加 `import SeamCarvingUIKit` 和 package product dependency |
| NSImage overload | 增加 `import SeamCarvingAppKit` 和 package product dependency |
| 自定义/非 Apple 图像类型 | 转为 `RGBA8Image`，使用 Core 或实现独立 adapter |

说明这是一项 v2 source-breaking target 重组，且兼容层只覆盖 Runtime/Imaging。

- [ ] **Step 3: 最终验证并提交**

Run: `bash Scripts/check-target-boundaries.sh && swift build --target SeamCarvingCore && swift test --parallel`

Expected: 脚本无输出且退出 0；Core 独立构建、全部 SwiftPM 测试通过。

```bash
git add Scripts/check-target-boundaries.sh .github/workflows/core-portability.yml docs/migrations/v2-platform-targets.md
git commit -m "docs: publish v2 platform module migration"
```

## 后续平台落地准入标准（不属于本次代码变更）

创建 `SeamCarvingWasm`、`SeamCarvingAndroid` 或 `SeamCarvingWindows` 前，必须先写一页 design doc，明确：

1. 宿主图像类型与 `RGBA8Image` 的色彩空间、alpha、row-stride、orientation 转换规则；
2. 默认 CPU backend 与可选 GPU backend 的能力和失败语义；
3. image I/O 库、许可、二进制体积和 cancellation 策略；
4. 真机、emulator 或目标 toolchain CI；
5. 至少一个 round-trip、orientation/stride、resize target-size 测试。

没有满足五项时，只能声明“架构预留”，不能宣称平台支持。

## 自检结果

- **覆盖性：** Tasks 1–2 保护 Core/runtime 边界；Tasks 3–4 拆解所有 Apple 图像类型；Task 5 迁移消费者；Task 6 防止依赖回流；准入标准约束未来平台。
- **无占位符：** 每个 target、文件、API、测试命令、完成标准和提交范围均已定义。
- **类型一致性：** adapter 间的稳定数据边界为 `RGBA8Image`、`PixelSize`、`ResizeOptions`、`SeamPath`；系统图像 API 均为 `AppleSeamCarver` extension。
