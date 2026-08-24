# 跨平台 Target 架构决策

## 目标

让 seam-carving 算法、后端选择和各平台图像对象的适配彼此独立。新增 WebAssembly、Android 或 Windows 支持时，应新增适配/运行时 target，而不是将平台条件编译扩散到 `SeamCarvingCore` 或应用逻辑。

## 分层与依赖方向

```text
SeamCarvingCore
├── SeamCarvingAccelerate                 (Apple 可选计算能力)
├── SeamCarvingMetal                      (Apple 可选计算能力)
├── SeamCarvingAppleRuntime               (Core + Accelerate + Metal)
│   └── Apple 的 backend 选择与 RGBA8 运算入口
│
├── SeamCarvingAppleImaging               (AppleRuntime + CoreGraphics + CoreImage)
├── SeamCarvingCoreVideo                  (AppleRuntime + CoreVideo)
├── SeamCarvingUIKit                      (AppleImaging + UIKit)
└── SeamCarvingAppKit                     (AppleImaging + AppKit)

未来：
SeamCarvingWasm / SeamCarvingAndroid / SeamCarvingWindows
└── SeamCarvingCore + 各自的像素缓冲或图像对象 bridge
```

依赖只允许由平台 adapter 指向 Core；`SeamCarvingCore`、其测试和公共 API 不得反向依赖 Apple、UIKit、AppKit、CoreGraphics、CoreImage、CoreVideo、Metal、Accelerate 或 Vision。

## 模块职责

| Target | 责任 | 禁止包含 |
| --- | --- | --- |
| `SeamCarvingCore` | `RGBA8Image`、mask、seam 算法、CPU backend、通用错误与配置 | 所有系统图像/图形框架导入 |
| `SeamCarvingAppleRuntime` | Accelerate/Metal/CPU 的 Apple 默认选择；在 `RGBA8Image` 上执行 resize/findSeam | `CGImage`、`CIImage`、`CVPixelBuffer`、`UIImage`、`NSImage` |
| `SeamCarvingAppleImaging` | `CGImage`/`CIImage` bridge、方向标准化、Core Image Lanczos pre-scale | UIKit、AppKit、CoreVideo |
| `SeamCarvingCoreVideo` | `CVPixelBuffer` bridge | UIKit、AppKit |
| `SeamCarvingUIKit` | `UIImage` bridge 与 `UIImage.Orientation` | AppKit |
| `SeamCarvingAppKit` | `NSImage` bridge | UIKit、Catalyst 分支 |

## 条件编译规则

1. 算法 target 中不得出现 `#if os`、`#if canImport` 或 `targetEnvironment`。
2. 一个适配 target 只服务一组系统框架；只在 target 的边界文件使用 availability 注解或极少量编译条件。
3. 不为同一份实现同时提供 UIKit/AppKit API；二者分别属于独立 target。
4. 运行时 fallback（Metal → Accelerate → CPU）是 capability 选择，不是 OS 分支，应封装在 `SeamCarvingAppleRuntime`。
5. 缺少可选能力时应返回明确的 `SeamCarvingError.invalidConfiguration`，而不是静默改变算法或隐藏 API。

## 公共 API 与兼容性

此次拆分是一次 **2.0 的 source-breaking 模块重组**：

- `SeamCarvingApple` 改为兼容性产品，只重新导出 `SeamCarvingAppleRuntime` 与 `SeamCarvingAppleImaging`。
- `UIImage` 调用方必须额外 `import SeamCarvingUIKit`；`NSImage` 调用方必须额外 `import SeamCarvingAppKit`。
- `AppleSeamCarver` 保持类型名、配置名、CGImage resize/findSeam 的签名不变；只有它们所属的模块被调整。
- v2 期间不把 UIKit 和 AppKit 再放入兼容层，以免重新引入互斥 framework 的条件编译。

## 支持承诺

- `Package.platforms: [.iOS(.v17), .macOS(.v14)]` 表示 Apple 侧的 deployment floor；它约束 Apple API 的最低系统版本，不是 Apple-exclusive host restriction。
- v2 立即支持：Apple 平台（iOS 17+、macOS 14+）的现有功能。
- v2 立即验证：`SeamCarvingCore` 的 portability 由 macOS/Linux/Windows Core CI gate 决定；只有对应 toolchain 实际通过 `swift build --target SeamCarvingCore` 与 `swift test --filter SeamCarvingCoreTests`，才算该宿主构建被验证。
- v2 预留：Wasm、Android、Windows 的 adapter contract；它们在各自 toolchain、图像 I/O 和 CI 可用前不列为已支持的平台。
