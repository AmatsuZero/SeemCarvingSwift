# SeamCarvingSwift

SeamCarvingSwift 是一个 Swift 6 内容感知图像缩放项目，支持 iOS 17+ 和
macOS 14+。项目包含平台无关的 RGBA8 seam-carving 引擎、可选的 Accelerate
和 Metal 后端、Apple 图像桥接、Vision 人脸保护、CLI，以及同时运行在
iPhone、iPad 和 Mac Catalyst 上的一套 SwiftUI App。

**语言 / Language：** [中文](README.zh-CN.md) · [English](README.md)

## 从哪里开始

| 目标 | 文档 |
|---|---|
| 了解模块边界和数据流 | [项目架构](docs/architecture-zh.html) · [English](docs/architecture.html) |
| 了解能量、seam、mask、放大和 Metal | [算法原理](docs/principles-zh.html) · [English](docs/principles.html) |
| 集成 Swift library | [Swift API 指南](docs/api-zh.html) · [English](docs/api.html) |
| 使用命令行和批处理 | [CLI 指南](docs/cli-zh.html) · [English](docs/cli.html) |
| 运行 iPhone/iPad/Catalyst 编辑器 | [App 指南](docs/app-zh.html) · [English](docs/app.html) |
| 查看能力和验收状态 | [能力矩阵](docs/capability-matrix-zh.html) · [English](docs/capability-matrix.html) |
| 浏览静态站点 | [中文站点](docs/index-zh.html) · [English site](docs/index.html) |

## 快速开始

### 构建 package

```sh
swift build
swift test
swift run seamcarve-cli --help
```

Package 使用 Swift tools 6.0，平台下限为 iOS 17 和 macOS 14。唯一的外部
package 依赖是 Apple 的
[`swift-argument-parser`](https://github.com/apple/swift-argument-parser)，用于 CLI
参数语法层。

### 使用 Core API

Core 接受 upright、origin-zero、straight-alpha 的 row-major RGBA8 字节，
不导入 UIKit、AppKit、Core Image、Vision、Metal 或 Accelerate。

```swift
import SeamCarvingCore

let image = try RGBA8Image(width: 4, height: 4, pixels: pixels)
let target = try PixelSize(width: 3, height: 4)
let result = try await SeamCarver().resize(image, to: target)
```

Mask、进度、取消、放大和 Apple facade 示例见 [Swift API 指南](docs/api-zh.html)。

### 按所用能力导入 Apple 模块

v2 的 `SeamCarvingApple` product 是仅面向 CGImage 的兼容 facade：它只重新导出
`SeamCarvingAppleRuntime` 和 `SeamCarvingAppleImaging`。UIKit 与 AppKit 是独立
product，必须显式导入。

```swift
// CGImage API / v2 兼容 facade
import SeamCarvingCore
import SeamCarvingApple

let carver = try AppleSeamCarver()
let output = try await carver.resize(cgImage, toPixelSize: target)
```

```swift
// iOS、iPadOS、Mac Catalyst 的 UIImage overload
import SeamCarvingCore
import SeamCarvingAppleRuntime
import SeamCarvingUIKit

let output = try await AppleSeamCarver().resize(uiImage, toPixelSize: target)
```

```swift
// macOS 的 NSImage overload
import SeamCarvingCore
import SeamCarvingAppleRuntime
import SeamCarvingAppKit

let output = try await AppleSeamCarver().resize(nsImage, toPixelSize: target)
```

每个直接导入的模块都应添加对应的 SwiftPM product dependency；不要用 facade 隐藏
Runtime、Imaging、UIKit 或 AppKit 依赖。

### 跨宿主边界状态

`SeamCarvingCore` 现在由 macOS 本地的 **仅 Core 构建 + 隔离测试 gate** 与
macOS/Linux/Windows CI 验证矩阵共同保护。只有仓库 CI 实际记录了
`swift build --target SeamCarvingCore` 与隔离后的 Core test target 成功，才应把
Linux/Windows 记为“已验证”。该 gate 验证的是可移植算法 target，并不代表这些
宿主的完整图像 I/O 或 App 已受支持。Wasm 与 Android 已预留 adapter 边界，但
目前均不是已支持的平台。

### 使用 CLI

```sh
swift run seamcarve-cli input.jpg output.png --width 1200 --height 800
swift run seamcarve-cli input.jpg output.jpg --percentage 75 --backend automatic
swift run seamcarve-cli --input-dir photos --output-dir resized \
  --width 1200 --height 800 --recursive --concurrency 2
```

`seamcarve-cli` 支持本地文件、明确的 `http(s)` URL，以及用 `-` 表示 stdin/
stdout。exact、percentage、square、backend、energy、order、pre-scale、mask、人脸
保护、debug artifact、输出格式和批处理参数见 [CLI 指南](docs/cli-zh.html)。

当前 CLI 的图像 I/O 有意保持 Apple-specific：它使用 ImageIO 和 CoreGraphics。未来
的跨宿主拆分会将参数、验证和 pipeline orchestration 放在 `SeamCarvingCLIModel`，并将
这些 codec 放在 `SeamCarvingAppleCLIImageIO`。这只是文档中的未来边界；本版本不提供
非 Apple 图像 I/O。

### 构建 App

App 使用一个 SwiftUI target，覆盖 iPhone、iPad 和 Mac Catalyst。Xcode project
由 `Apps/SeamCarvingApp/project.yml` 本地生成，并被 Git 忽略。

```sh
cd Apps/SeamCarvingApp
xcodegen generate
xcodebuild -project SeamCarvingApp.xcodeproj -scheme SeamCarvingApp \
  -destination 'generic/platform=iOS' build
xcodebuild -project SeamCarvingApp.xcodeproj -scheme SeamCarvingApp \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO build
```

导入、目标尺寸、mask、人脸保护、导出、签名和平台测试见 [App 指南](docs/app-zh.html)。

## 引擎能力

Core 逐条删除或插入 connected seam，支持：

- backward Sobel 和 forward-luma energy；
- width-first、height-first、adaptive normalized-cost 顺序；
- hard/soft protection mask 和 weighted removal mask；
- 对象移除，以及可选恢复原始尺寸；
- progress、cooperative cancellation 和 seam observation；
- 默认精确的逐 seam 语义；
- 显式 Apple-only Lanczos 预缩放 + exact residual carving；
- 通过 `AppleSeamCarver` 选择 CPU、Accelerate、Metal；
- Vision 人脸保护，支持 Caire-inspired/Vision-quality policy 和两种 cadence。

[能力矩阵](docs/capability-matrix-zh.html) 是产品状态的权威记录。Caire 只是能力
对齐参考；本项目不声称 Caire 兼容，也不使用 Caire detector。

## 后端和限制

`.automatic` 依次尝试 Metal、Accelerate、CPU；需要可复现结果时使用
`.deterministic` 或 `.cpu`。Metal 是可选异步后端：支持的 shrink 路径会加速，
横向编辑使用 CPU transpose，放大和 adaptive order 使用 CPU 参考路径。CLI debug
artifact 需要 seam observation，因此会使用 CPU。

默认 `PreScaleStrategy.none` 不会隐式 Lanczos。`.lanczosThenExactResidual` 是
显式的 Apple-only 近似，会先缩放图像和 mask，再进行 exact residual carving。

项目不包含视频 temporal coherence、learned saliency、transport maps、MLX、Core ML、
HDR/extended-range canonical input，也不提供 GPU-only 合同。

## 架构概览

```text
SeamCarvingCore
    ├── SeamCarvingAccelerate
    ├── SeamCarvingMetal
    ├── SeamCarvingAppleRuntime
    │   ├── SeamCarvingAppleImaging ──┬── SeamCarvingVision
    │   │                             ├── SeamCarvingCLI / seamcarve-cli
    │   │                             └── shared SwiftUI app
    │   ├── SeamCarvingCoreVideo
    │   ├── SeamCarvingUIKit
    │   └── SeamCarvingAppKit
    └── SeamCarvingApple（CGImage compatibility facade）
```

Core 负责图像/mask 语义、energy、dynamic programming、seam editing、planning 和 CPU
oracle。AppleRuntime 选择 backend，AppleImaging 负责 CGImage/Core Image bridge，
CoreVideo/UIKit/AppKit target 各自拥有对应系统图像类型。Vision 将人脸观察结果转成
Core mask。

## 测试与真实限制

```sh
swift test --package-path . --parallel
```

最近一次记录的 package regression 为 169 个测试通过，包含 Metal parity 和 shrink
smoke。Apple App 验收记录包括：

- iPhone/iPad Simulator：31 个单测 + 2 个 UI 测试通过；
- Mac Catalyst：clean build + 31 个单测通过；
- 连接的 iPad 真机：签名、安装和 31 个单测通过；
- iPad 真机 UI XCTest：**未通过**，runner 在启用 automation mode 前超时，未进入
  UI 测试方法；
- 真机 Metal：已有签名 16/16 screening 记录，但发布前需要专用签名 Metal host
  重跑。

详细命令、日期和限制见
[`Apps/SeamCarvingApp/Tests/AcceptanceMatrix.md`](Apps/SeamCarvingApp/Tests/AcceptanceMatrix.md)。
如果 App 能正常启动，`LSPrefs`、`FSFindFolder`、`ViewBridge`、task-port 等日志属于
Xcode/macOS 系统诊断，不应通过危险 entitlement 隐藏。

## GitHub Pages

站点是无需构建工具的静态 HTML/CSS。仓库 **Settings → Pages → Deploy from a branch**，
选择分支并将目录设置为 **`/docs`** 即可发布；无需 Jekyll、Node、Python 或文档构建步骤。

## 目录结构

```text
Sources/SeamCarvingCore/        平台无关引擎
Sources/SeamCarvingAccelerate/  Accelerate 后端
Sources/SeamCarvingMetal/       Metal 后端与 shader
Sources/SeamCarvingAppleRuntime/ Apple backend 选择与 RGBA8 API
Sources/SeamCarvingAppleImaging/ CGImage/CIImage adapter
Sources/SeamCarvingCoreVideo/    CVPixelBuffer adapter
Sources/SeamCarvingUIKit/        UIImage adapter
Sources/SeamCarvingAppKit/       NSImage adapter
Sources/SeamCarvingApple/        CGImage compatibility facade
Sources/SeamCarvingVision/      Vision 人脸保护适配器
Sources/SeamCarvingCLI/         CLI 参数、I/O、批处理、artifact
Sources/seamcarve-cli/          CLI 入口
Apps/SeamCarvingApp/            SwiftUI 编辑器和验收测试
docs/                           Markdown 记录和 GitHub Pages HTML
```
