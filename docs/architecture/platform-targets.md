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

Android（已实现为独立 Gradle library）：
SeamCarvingAndroidBridge
└── SeamCarvingCore + JNI-safe RGBA bridge
    └── seamcarving-android-core（RGBA/mask + native runtime）
        ├── seamcarving-android-bitmap（Bitmap adapter）
        ├── seamcarving-android-mlkit（可选 face-protection mask）
        └── seamcarving-android（默认 core + Bitmap facade）

未来：
SeamCarvingWasm / SeamCarvingWindows
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
| `SeamCarvingAndroidBridge` | 仅将 `RGBA8Image`、目标尺寸、mask 与 progress/cancel bridge 到 JNI | Android/ML Kit import、Apple backend、公开 JNI API |
| `seamcarving-android-core` | 稳定 Kotlin RGBA/mask API、native runtime 与 CPU carving | `Bitmap`、ML Kit、重复 runtime library |
| `seamcarving-android-bitmap` | `Bitmap` 与 RGBA8 的显式 `AARRGGBB` 转换 | native `.so`、ML Kit |
| `seamcarving-android-mlkit` | Android ML Kit face box 到保护 mask | Swift import、默认 facade 的传递依赖 |

## 条件编译规则

1. `SeamCarvingCore`、`SeamCarvingAppleRuntime`、`SeamCarvingAppleImaging` 与 `SeamCarvingCoreVideo` 中不得出现条件编译；`SeamCarvingCore` 只能导入可移植的 `Foundation`/`Dispatch`。
2. UIKit 与 AppKit 是唯一的窄例外：为让 SwiftPM 在不具备相应 framework 的宿主上发现 target，每个 adapter 源文件可使用唯一的、包住整个文件的 `#if canImport(UIKit)` 或 `#if canImport(AppKit)` guard。禁止 `#elseif`、`#else`、内层条件、`targetEnvironment` 与 sibling framework import。
3. 不为同一份实现同时提供 UIKit/AppKit API；二者分别属于独立 target。
4. 运行时 fallback（Metal → Accelerate → CPU）是 capability 选择，不是 OS 分支，应封装在 `SeamCarvingAppleRuntime`。
5. 缺少可选能力时应返回明确的 `SeamCarvingError.invalidConfiguration`，而不是静默改变算法或隐藏 API。
6. Android 的 stable external API 只限 Kotlin 的 `io.github.seamcarving` package；swift-java
   生成的 Java/JNI 类和 Swift runtime 均为实现细节。`RgbaImage` 是 upright、origin-zero、
   straight-alpha、row-major RGBA8，且 byte count 必须为 `width * height * 4`。
7. Android `Bitmap` adapter 使用 `getPixels()`/`setPixels()` 显式转换 `AARRGGBB`，不能依赖
   backing storage 的 byte order 或 row stride。ML Kit 人脸检测和保护 mask 只在 optional
   Gradle artifact 中实现，Swift 侧不导入 Android 或 ML Kit。

## 公共 API 与兼容性

此次拆分是一次 **2.0 的 source-breaking 模块重组**：

- `SeamCarvingApple` 改为兼容性产品，只重新导出 `SeamCarvingAppleRuntime` 与 `SeamCarvingAppleImaging`。
- `UIImage` 调用方必须额外 `import SeamCarvingUIKit`；`NSImage` 调用方必须额外 `import SeamCarvingAppKit`。
- `AppleSeamCarver` 保持类型名、配置名、CGImage resize/findSeam 的签名不变；只有它们所属的模块被调整。
- v2 期间不把 UIKit 和 AppKit 再放入兼容层，以免重新引入互斥 framework 的条件编译。

## 支持承诺

- `Package.platforms: [.iOS(.v17), .macOS(.v14)]` 表示 Apple 侧的 deployment floor；它约束 Apple API 的最低系统版本，不是 Apple-exclusive host restriction。
- v2 立即支持：Apple 平台（iOS 17+、macOS 14+）的现有功能。
- v2 立即验证：仓库当前仅以 manifest 隔离后的 `SeamCarvingCoreTests` 本地证明 macOS Core gate；Linux/Windows 仍是 CI 验证 gate，只有仓库 CI 实际通过 `swift build --target SeamCarvingCore` 与隔离后的 Core tests 后，才能把对应宿主记为已验证。
- Android 当前支持：`minSdk 28` 的 CPU Gradle library。Core AAR 只为
  `arm64-v8a`、`armeabi-v7a`、`x86_64` 打包 Swift/C++ runtime；默认 facade 包含 Core +
  Bitmap、明确排除 ML Kit。消费者不安装 Swift/NDK；仓库构建则固定 Swift 6.3.3、对应
  Android SDK 与 NDK r27d。Kotlin Flow 的取消会协作式取消 native resize。
- Android 不支持：Apple CLI、SwiftUI app、ImageIO/CoreGraphics codec、Accelerate、Metal 或
  Vision。远端 Maven Central 上传和签名是独立 credential-gated release 流程，常规 CI 只
  验证本地 Maven publication 与外部 consumer。
- v2 预留：Wasm、Windows 的 adapter contract；它们在各自 toolchain、图像 I/O 和 CI 可用前不列为已支持的平台。
