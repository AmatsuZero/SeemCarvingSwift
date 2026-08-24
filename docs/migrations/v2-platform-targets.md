# v2 平台 Target 迁移指南

v2 将原先的 Apple 图像 API 按能力拆分为独立 SwiftPM products。这是一次
**source-breaking 的模块重组**：算法 API 和图像处理语义不变，但调用方必须把
需要的图像 adapter 显式加入 package dependency 并 `import` 对应模块。

## v1 → v2 精确映射

| v1 import / API 用法 | v2 package dependency 与 import | 兼容性 |
| --- | --- | --- |
| `SeamCarvingCore` 的 `RGBA8Image`、mask、CPU API | `SeamCarvingCore`；`import SeamCarvingCore` | 不变 |
| `SeamCarvingAccelerate` 或 `SeamCarvingMetal` | 同名 product；保留原 import | 不变 |
| `SeamCarvingVision`、`SeamCarvingCLI` 或 `SeamCarvingBenchmark` | 同名 product；保留原 import | 调用方不变；其内部改为直接依赖 capability products |
| `import SeamCarvingApple` + `CGImage` `resize` / `findSeam` | 可保持 `SeamCarvingApple` product/import；也可改为 `SeamCarvingAppleRuntime` + `SeamCarvingAppleImaging` | facade 兼容 |
| `import SeamCarvingApple` + `CIImage` `resize` | 可保持 `SeamCarvingApple` product/import；也可改为 `SeamCarvingAppleRuntime` + `SeamCarvingAppleImaging` | facade 兼容 |
| `import SeamCarvingApple` + `AppleSeamCarver` 的 `RGBA8Image` API | 可保持 `SeamCarvingApple` product/import；新增调用方应直接使用 `SeamCarvingAppleRuntime` | facade 兼容 |
| `import SeamCarvingApple` + `UIImage` `resize` | `SeamCarvingAppleRuntime` + `SeamCarvingUIKit`；`import SeamCarvingAppleRuntime`、`import SeamCarvingUIKit`（以及应用本身的 `UIKit`） | 必须迁移 |
| `import SeamCarvingApple` + `NSImage` `resize` | `SeamCarvingAppleRuntime` + `SeamCarvingAppKit`；`import SeamCarvingAppleRuntime`、`import SeamCarvingAppKit`（以及应用本身的 `AppKit`） | 必须迁移 |
| `import SeamCarvingApple` + `CVPixelBuffer` `resize` | `SeamCarvingAppleRuntime` + `SeamCarvingCoreVideo`；`import SeamCarvingAppleRuntime`、`import SeamCarvingCoreVideo`（使用 orientation 参数时同时 import `ImageIO`） | 必须迁移 |
| 自定义、Wasm、Android 或 Windows 图像类型 | `SeamCarvingCore`；转换为 `RGBA8Image`，或实现只依赖 Core 的新 adapter | 无 Apple facade 兼容层 |

## 迁移示例

### UIImage

```swift
// v1
import SeamCarvingApple

// v2
import SeamCarvingAppleRuntime
import SeamCarvingUIKit
import UIKit
```

把 `SeamCarvingAppleRuntime` 和 `SeamCarvingUIKit` 都加入 SwiftPM target 的
dependencies。`UIImage` overload 的调用形式保持不变。

### NSImage

```swift
// v1
import SeamCarvingApple

// v2
import AppKit
import SeamCarvingAppKit
import SeamCarvingAppleRuntime
```

把 `SeamCarvingAppleRuntime` 和 `SeamCarvingAppKit` 都加入 dependencies。

## `SeamCarvingApple` compatibility facade 的范围

`SeamCarvingApple` 在 v2 仅重新导出：

- `SeamCarvingAppleRuntime`
- `SeamCarvingAppleImaging`

因此它兼容 `AppleSeamCarver` 的 `RGBA8Image`、`CGImage` 与 `CIImage` 表面；它**不会**重新导出
`SeamCarvingUIKit`、`SeamCarvingAppKit` 或 `SeamCarvingCoreVideo`。这避免同一个
target 混入 UIKit/AppKit 的互斥平台依赖。需要 `UIImage`、`NSImage` 或
`CVPixelBuffer` 的调用方必须显式采用上表对应的 capability product。

## 平台支持边界

v2 的 Apple deployment floor 仍为 iOS 17+ 与 macOS 14+。`SeamCarvingCore`
当前以 manifest 隔离后的 Core tests 在 macOS 本地证明可移植边界；Linux/Windows
仍是 CI 验证 gate，只有仓库 CI 实际跑通 `swift build --target SeamCarvingCore`
与隔离后的 Core tests 后，才能把对应宿主记为已验证。这不代表整个 package 已在
这些宿主上得到支持。Wasm、Android、Windows adapter 目前仅为架构预留，必须先
拥有各自的图像 bridge、目标 toolchain CI 和测试，才能宣称支持。
