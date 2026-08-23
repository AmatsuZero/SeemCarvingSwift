# Caire 产品能力对齐实施计划

**日期：** 2026-08-23  
**目标：** 在不追求 Caire/Pigo API 或像素级兼容的前提下，补齐 Caire 用户可感知、且适合 Apple 生态产品化的剩余能力。

## Goal

让 SeamCarvingSwift 在 CLI、Core/Apple 服务层和 macOS/iPhone/iPad GUI 上覆盖 Caire README 中仍未覆盖的主要产品能力：

1. CLI 的百分比/正方形缩放、stdin/stdout、URL 输入、BMP 输出；
2. 递归目录批处理与受控并发；
3. blur、Sobel threshold、debug/seam visualization 等可解释的处理控制；
4. GUI 的对象移除后恢复原尺寸流程；
5. GUI 的人脸检测预览、编辑和统一的 face-aware workflow；
6. 跨平台导入/导出和手工验收闭环。

以 [Caire README](https://github.com/esimov/caire) 的公开功能列表为外部基准，以当前 `docs/capability-matrix.md` 和仓库测试为内部基准。

## Architecture

- **保持分层：** Core 负责 seam carving/energy/mask 语义，Apple 负责 CGImage、Vision、Accelerate/Metal 和 ImageIO，CLI 负责参数、I/O、批处理，SwiftUI App 负责交互和平台适配。
- **CLIEntry 变薄：** 将解析后的配置、单图处理、I/O、批处理拆为可测试的值类型/服务；`@main` 只负责退出码和 stderr/stdout 编排。
- **配置单一来源：** percentage/square/blur/Sobel/debug 必须落到类型化配置并传递到实际 engine，不能只增加“接受但忽略”的 CLI flag。
- **二进制流安全：** `-` 输入/输出时，stdout 只能写图像字节；诊断和 progress 一律 stderr。普通路径模式下保持现有文本结果和错误退出码语义。
- **GUI 与 CLI 共用服务语义：** object removal、restore-original-size、face detection cadence 和 debug overlay 不在 UI 中复制一份算法。
- **默认行为不变：** 未指定新增选项时，现有 pixel target、backward/forward、mask、backend、deterministic 和 PNG/JPEG 行为必须保持兼容。

## Tech Stack

- Swift Package Manager、Swift 6、XCTest
- CoreGraphics / ImageIO / UniformTypeIdentifiers
- Accelerate / Metal（已有 Apple backend）
- Vision（已有 face detector）
- SwiftUI、PhotosPicker、fileImporter、macOS NSOpenPanel/NSSavePanel
- iPad 真机作为 Metal 和 GUI acceptance device

## Spec

### 外部能力基线

Caire README 列出 GUI progress、CLI shrink/enlarge、vertical/horizontal resize、face detection、多种输出格式、stdin/stdout、递归并发目录处理、Sobel threshold、blur、square/proportional scaling、protective/removal mask 和 GUI debug mode。当前仓库已验证大部分基础 resize、energy、mask、pre-scale、backend、progress、跨 Apple 平台和 PNG/JPEG；明确未完成的是：

- CLI scalar modes 和 I/O/batch parity；
- blur/Sobel threshold 的实际算法参数；
- debug/seam visualization 的可消费产物；
- GUI restoration workflow；
- GUI face detection 的预览/编辑闭环；
- picker、face-image、debug overlay 的真实设备手工 smoke test。

### Non-goals

- 不实现 Go Caire 的 API、命令行逐字符兼容或 Pigo detector 兼容。
- 不承诺与 Caire 的逐像素结果相同；Vision detector、energy 实现和 backend 允许不同。
- 不在本阶段加入视频时间一致性、learned saliency、transport-map optimization 或自动云端处理。
- 不让 batch/debug 功能改变现有 exact mode 的默认性能和确定性语义。

## Global Constraints

- 每个任务先写/更新测试，再实现；任务完成后必须运行对应验证命令。
- 每个任务单独提交，提交信息使用 `feat: ...`、`test: ...` 或 `docs: ...` 前缀。
- 不修改用户未提交的 `CODE_REVIEW.md`。
- 不把构建产物、签名文件、真机临时文件或 `.xcodeproj` 生成差异提交进仓库。
- 新增公开配置必须有文档注释、默认值和非法值测试。
- 失败时使用 stderr 和稳定退出码；不要用 `fatalError` 处理用户输入。
- 完成前运行 package、host app、平台 simulator 和 iPad device 的必要验收；未能运行的真实设备测试必须明确记录原因。

## 当前基线

在开始新任务前确认：

```bash
git status --short
swift test --package-path . --parallel
```

当前已知基线：package tests 103/103；macOS/iOS/iPadOS App XCTest 和 iPad 真机 App XCTest 已通过；iPad Metal screening 16/16。若基线发生变化，先修复回归，不要把回归混入下面的功能提交。

## Task 1 — 冻结 parity contract，并拆分 CLI pipeline

**目的：** 为后续 Agent 提供稳定边界，避免所有新功能继续堆进 `CLIEntry.swift`。

**修改范围：**

- `Sources/SeamCarvingCLI/CLIOptions.swift`
- 新增 `Sources/SeamCarvingCLI/CLIConfiguration.swift` 或等价 typed configuration 文件
- 新增 `Sources/SeamCarvingCLI/CLIImageIO.swift`
- 新增 `Sources/SeamCarvingCLI/CLIProcessor.swift`
- `Sources/seamcarve-cli/CLIEntry.swift`
- `Tests/SeamCarvingCLITests/CLIOptionsTests.swift`
- `Tests/SeamCarvingCLITests/CLIEndToEndTests.swift`

**实现要求：**

1. 保留现有 positional `INPUT OUTPUT --width --height` 语法。
2. 为后续选项预留类型化字段：`percentage`、`square`、`blurRadius`、`sobelThreshold`、`debug`、`debugDirectory`、`seamColor`、`seamShape`、batch directory/concurrency。
3. 把“读取 CGImage → 构造 mask → 构造 ResizeOptions → 调用 Apple/FaceAware service → 写出结果”从 `CLIEntry` 抽为可单测 service。
4. 统一定义输入输出错误、unsupported format、mask size mismatch 和 cancellation 的退出码；stdout/stderr 契约写入 CLI 文档注释。
5. 新增 parser negative tests，确保未知 flag、重复 positional 参数、非正尺寸、非法 float、冲突 mode 都失败。

**验证：**

```bash
swift test --package-path . --filter CLIOptionsTests --parallel
swift test --package-path . --filter CLIEndToEndTests --parallel
```

**提交：** `refactor: split CLI processing pipeline`

## Task 2 — scalar resize modes 和 configurable energy controls

**目的：** 对齐 Caire 的 proportional/percentage、square、blur 和 Sobel threshold，且确保参数真正影响算法。

**修改范围：**

- `Sources/SeamCarvingCore/ResizePlanner.swift`
- `Sources/SeamCarvingCore/Energy.swift`
- `Sources/SeamCarvingCore/BackwardEnergy.swift`
- `Sources/SeamCarvingCore/CPUBackend.swift`
- `Sources/SeamCarvingApple/AppleSeamCarver.swift`
- `Sources/SeamCarvingApple/PreScale.swift`（仅必要时）
- `Sources/SeamCarvingCLI/CLIOptions.swift`
- `Sources/SeamCarvingCLI/CLIProcessor.swift`
- 对应 Core/Apple/CLI tests

**实现要求：**

1. 定义明确的 `ResizeMode` 或等价值类型：exact pixel target、percentage、square；percentage 以源尺寸为基准，四舍五入规则、最小尺寸 1 和 enlarge 行为写入文档并测试。
2. `square` 明确是否使用长边、短边或显式边长；推荐默认使用源图比例保留语义中可表达的目标边长，并拒绝歧义组合。不要让 `--square` 与显式 width/height 静默冲突。
3. blur radius 和 Sobel threshold 必须进入实际 energy 计算。默认值必须复现当前结果；CPU、Accelerate、Metal 路径要么支持相同语义，要么在 backend validation 时给出明确 unsupported 错误，不能忽略参数。
4. 对每种参数增加小图 golden/behavior tests：零值等于默认、非零 blur 改变能量、threshold 边界稳定、percentage 输出尺寸正确、square 输出为正方形。
5. 更新 `docs/capability-matrix.md`，将这些能力从 deferred 改为 verified 只能在测试完成后进行。

**验证：**

```bash
swift test --package-path . --parallel
swift test --package-path . --filter 'CLIOptionsTests|CLIEndToEndTests' --parallel
xcodebuild -scheme SeamCarvingSwift-Package -workspace . -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

**提交：** `feat: add scalar resize and energy controls`

## Task 3 — stdin/stdout、URL input 和 BMP I/O

**修改范围：**

- `Sources/SeamCarvingCLI/CLIImageIO.swift`
- `Sources/seamcarve-cli/CLIEntry.swift`
- `Sources/SeamCarvingCLI/CLIOptions.swift`
- `Tests/SeamCarvingCLITests/CLIEndToEndTests.swift`
- 必要时 `Package.swift`

**实现要求：**

1. `-` 作为 input 时从 `FileHandle.standardInput` 读取完整 binary data；`-` 作为 output 时把 encoded binary data 写到 stdout。
2. stdout binary mode 下禁止输出尺寸、progress 和诊断文本；诊断统一写 stderr。
3. URL input 使用 Foundation URLSession 或明确的 platform-safe downloader；必须限制为显式 URL 参数/URL 形态，不能把任意不存在的本地路径静默当 URL。网络失败要有稳定错误。
4. 基于 ImageIO 增加 BMP decode/encode（`UTType.bmp` 或对应 UTI），并覆盖 `.bmp`、大小写扩展名及显式 `--format`（如采用）测试。
5. 输出格式不能只看扩展名猜错；stdin/stdout 必须有 `--format` 或可解释的默认规则，并在帮助文本中说明。
6. 增加 shell-level test 或等价 process test，验证 binary round-trip、stderr 不污染 stdout 和错误退出码。

**验证：**

```bash
swift test --package-path . --filter CLIEndToEndTests --parallel
swift run --package-path . seamcarve-cli --help
```

**提交：** `feat: add CLI stream URL and BMP I/O`

## Task 4 — recursive batch processing and bounded concurrency

**修改范围：**

- 新增 `Sources/SeamCarvingCLI/BatchProcessor.swift`
- `Sources/SeamCarvingCLI/CLIConfiguration.swift`
- `Sources/seamcarve-cli/CLIEntry.swift`
- 新增/修改 `Tests/SeamCarvingCLITests/BatchProcessorTests.swift`
- CLI README/help 文档

**实现要求：**

1. 提供 `--input-dir`、`--output-dir`、`--recursive`、`--concurrency N`（名称可调整但必须稳定）的 batch contract。
2. 输入枚举按 normalized path 排序，支持 PNG/JPEG/BMP，忽略非图片文件；输出目录保持相对路径并创建父目录。
3. 使用 bounded `TaskGroup`/actor 计数器，不能一次性启动无限任务；`N > 0`，默认值保守且文档化。
4. 单文件失败要记录路径和错误；定义 fail-fast 或 continue-on-error 行为，推荐继续处理并最终返回非零退出码。
5. batch 模式与单图 stdin/stdout、debug sidecar 的冲突必须显式报错，不能产生互相覆盖的输出。
6. 统计成功/失败/跳过数量，诊断写 stderr；测试用 temporary directory 验证排序、并发上限、嵌套路径和部分失败。

**验证：**

```bash
swift test --package-path . --filter BatchProcessorTests --parallel
swift test --package-path . --filter CLIEndToEndTests --parallel
```

**提交：** `feat: add recursive bounded CLI batch processing`

## Task 5 — debug artifacts 和 seam visualization

**目的：** 覆盖 Caire GUI debug、seam color/shape 的产品能力，而不是增加一个无效的 `--debug` flag。

**修改范围：**

- `Sources/SeamCarvingCore/SeamCarver.swift`
- `Sources/SeamCarvingCore/SeamEditor.swift`
- 新增 typed seam observation/debug artifact API（优先保持 public API 最小）
- `Sources/SeamCarvingApple/CGImageBridge.swift` 或新增 overlay renderer
- CLI processor/options
- `Tests/SeamCarvingCoreTests/*`
- `Tests/SeamCarvingCLITests/*`

**实现要求：**

1. 先定义 artifact contract：debug 输出是 overlay image、逐 seam JSON/manifest，还是两者；明确坐标系、orientation、颜色、shape（line/points）和输出路径。
2. seam observation 必须尊重 cancellation、dimension order 和 mask 后的实际 seam；不能从最终图像反推假 seam。
3. 默认关闭且零额外开销；batch 模式默认关闭，启用时使用 sidecar directory，不污染目标图像和 stdout。
4. 颜色必须解析为明确 RGBA；shape 和 debug level 非法时在 parser 阶段失败。
5. 用 5x5/非正方形 fixture 验证 seam 坐标、orientation、颜色 alpha、sidecar 命名和最终图像尺寸；加入 cancellation test。
6. 若 Metal full path 无法提供逐 seam observation，必须记录降级策略（例如 debug 强制 CPU/Accelerate）并在 CLI/UI 明示，不能声称 Metal debug 与普通模式等价。

**验证：**

```bash
swift test --package-path . --parallel
swift test --package-path . --filter 'Seam|CLI' --parallel
```

**提交：** `feat: add seam debug artifacts`

## Task 6 — GUI object removal and restore-original-size workflow

**修改范围：**

- `Apps/SeamCarvingApp/Sources/Shared/ResizeConfiguration.swift`
- `Apps/SeamCarvingApp/Sources/Shared/AppModel.swift`
- `Apps/SeamCarvingApp/Sources/Shared/ContentView.swift`
- `Apps/SeamCarvingApp/Sources/Shared/ResizeDocument.swift`
- `Sources/SeamCarvingCore/SeamCarver.swift`（仅必要 API 调整）
- `Apps/SeamCarvingApp/Tests/*`

**实现要求：**

1. 增加显式的 object-removal mode 和 `restoreOriginalSize` 配置，区分“普通 resize 使用 removal mask”和“移除对象后回填到原尺寸”。
2. AppModel/service 调用 Core 的 `SeamCarver.removeObject(...restoreOriginalSize:)`，不要在 UI 层重复实现删除/恢复。
3. UI 提供模式切换、目标尺寸/恢复尺寸说明、运行中进度、取消和完成后尺寸显示；普通模式行为不变。
4. 完成后正确更新 working image、target metadata 和 mask 状态；source image 始终不可变，取消后可继续编辑/重试。
5. 测试 fake service 调用参数；Core fixture 测试输出尺寸恢复；App XCTest 覆盖 mode toggle、cancel、failure 和 export guard。

**验证：**

```bash
swift test --package-path . --parallel
xcodebuild -scheme SeamCarvingTestHost -project Apps/SeamCarvingTestHost/SeamCarvingTestHost.xcodeproj -destination 'platform=macOS' test
```

**提交：** `feat: expose GUI object removal restoration`

## Task 7 — GUI face detection preflight and editable regions

**修改范围：**

- `Apps/SeamCarvingApp/Sources/Shared/AppModel.swift`
- `Apps/SeamCarvingApp/Sources/Shared/FaceProtectionControlsView.swift`
- `Apps/SeamCarvingApp/Sources/Shared/ResizeConfiguration.swift`
- `Apps/SeamCarvingApp/Sources/Shared/ResizeDocument.swift`
- `Sources/SeamCarvingVision/*`（仅统一 detector revision/metadata 所需）
- App XCTest fixtures/tests

**实现要求：**

1. 增加显式 “Detect faces” action，在 resize 前通过同一 Vision detector/revision 生成 face regions。
2. 将 region 坐标转换为当前显示坐标，绘制 overlay；允许逐个排除/恢复，并把 exclusions 传给实际 face-aware service。
3. 明确 detect-once 与 redetect-each-pass 的含义；重复检测不能导致 UI region index 不稳定。优先使用 stable IDs，而不是数组下标。
4. 无脸、Vision 失败、取消和旋转/EXIF orientation 都要有可解释状态；不得因检测失败静默关闭保护。
5. 用注入 fake detector 做 region/exclusion/cadence tests；在有图片条件时补充 macOS/iPad 真机真实人脸 smoke test。

**验证：**

```bash
swift test --package-path . --parallel
xcodebuild -scheme SeamCarvingTestHost -project Apps/SeamCarvingTestHost/SeamCarvingTestHost.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**提交：** `feat: add editable GUI face detection workflow`

## Task 8 — platform import/export polish and acceptance

**修改范围：**

- `Apps/SeamCarvingApp/Sources/Shared/ContentView.swift`
- `Apps/SeamCarvingApp/Sources/macOS/MacPlatformServices.swift`
- `Apps/SeamCarvingApp/Sources/iOS/IOSPlatformServices.swift`
- App tests and `docs/capability-matrix.md`

**实现要求：**

1. 验证 macOS open/save、drag/drop（如采用）、iPhone/iPad PhotosPicker/fileImporter、PNG/JPEG/BMP export 的真实交互路径。
2. 对 import cancellation、unsupported type、large image、orientation 和 export before completion 提供稳定 UI 状态。
3. 将 debug overlay、face rectangles、object-removal result 在三平台 adaptive layout 中可见；不把 iPad-only 控件写死在平台共享视图。
4. 更新 capability matrix，只标记已经有自动化或真实设备证据的能力为 verified；未运行的手工项标记 recommended/manual pending。

**验证：**

```bash
swift test --package-path . --parallel
xcodebuild -scheme SeamCarvingTestHost -project Apps/SeamCarvingTestHost/SeamCarvingTestHost.xcodeproj -destination 'platform=macOS' test
xcodebuild -scheme SeamCarvingTestHost -project Apps/SeamCarvingTestHost/SeamCarvingTestHost.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16' test
xcodebuild -scheme SeamCarvingTestHost -project Apps/SeamCarvingTestHost/SeamCarvingTestHost.xcodeproj -destination 'platform=iPad (10th generation)' test
```

有连接的 iPad 时，再执行真机 App XCTest 和 Metal screening；记录设备、commit、测试数量和失败原因。

**提交：** `test: complete multiplatform capability acceptance`

## Task 9 — 文档、回归和交付审计

**修改范围：**

- `README.md` 或 CLI 文档入口
- `docs/capability-matrix.md`
- `docs/superpowers/plans/` 中的执行记录（如需要）
- 新增功能的 doc comments

**实现要求：**

1. 为每个 Caire-inspired flag 给出语法、默认值、互斥关系、输出示例和平台限制。
2. 给出“能力对齐”与“实现差异”章节，明确 Vision/Caire policy 不等于 Pigo/API compatibility。
3. 记录 benchmark/设备验收，不把 benchmark 结果当作功能正确性证明。
4. 运行全量测试、`git diff --check`、构建和 capability matrix 审计；确认没有新增 ignored/generated files 被误提交。

**验证：**

```bash
swift test --package-path . --parallel
git diff --check
git status --short
```

**提交：** `docs: document completed Caire capability alignment`

## Recommended execution order for another Agent

按 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 顺序执行。Task 2–5 是 CLI/Core 主线，Task 6–8 是 GUI 主线；如果使用多个 Agent：

- Agent A：Task 1–4（CLI/I/O/batch）；
- Agent B：Task 5（debug artifact，需先读 Core seam lifecycle）；
- Agent C：Task 6–7（GUI object removal + face workflow）；
- Agent D：Task 8–9（在 A/B/C 合并后做跨平台验收和文档）。

Task 5、6、7 都会触及共享模型/API，不能在未完成 Task 1/2 的 contract review 前并行修改同一文件。每个 Agent 完成后先提交，再由独立 reviewer 检查测试和是否存在“flag 被接受但没有生效”的实现。

## Definition of Done

- Caire README 中纳入范围的能力都有对应 typed API、CLI/UI 入口和自动化测试。
- 新增 CLI 选项不会污染 binary stdout，batch 并发有上限，默认行为保持兼容。
- object removal restoration 和 face detection 都能在 GUI 中真实触发，且有 fake-service/fake-detector 测试。
- macOS、iPhone、iPad 的宿主测试通过；可用时 iPad 真机 App XCTest 和 Metal screening 通过。
- `docs/capability-matrix.md`、README/help 文本与实际行为一致。
- 所有任务均有独立提交，工作树只保留用户已有的未跟踪文件或明确记录的变更。

## 执行记录（Execution Record）

### Task 1 — 条件通过

> **条件通过：** 预留参数已禁止静默忽略；公开 API 兼容性和 progress sink 仍需后续明确/修改。可以开始执行 Task 2。

- **提交：**
  - `d03b126` `refactor: split CLI processing pipeline`
  - `d796766` `fix: reject reserved CLI options instead of ignoring them`（复审修复）
- **验证：**
  - `swift test --package-path . --filter CLIOptionsTests --parallel` → 通过（27 测试）
  - `swift test --package-path . --filter CLIEndToEndTests --parallel` → 通过（6 测试，需 `SEAMCARVE_CLI_PATH`）
  - `swift test --package-path . --parallel` → 125/125 通过，`git diff --check` 干净
- **改动摘要：**
  - `Sources/SeamCarvingCLI/CLIConfiguration.swift`（新增）：`ResizeMode`、`SeamColor`、`SeamShape`、`CLIExitCode`（sysexits 64/65/70/130）、`CLIConfigurationError`，stdout/stderr 契约写入 doc comment。
  - `Sources/SeamCarvingCLI/CLIImageIO.swift`（新增）：`readImage`/`loadMask`/`writeImage` 与 `CLIImageIOError`（decode、unsupported format、mask size mismatch、encode）。
  - `Sources/SeamCarvingCLI/CLIProcessor.swift`（新增）：把“读图 → 构造 mask → 构造 ResizeOptions → 调用 Apple/FaceAware service → 写出”抽为可单测 service，返回 `CLIProcessResult`。
  - `CLIOptions.swift`：保留 positional `INPUT OUTPUT --width --height` 语法；预留类型化字段（`percentage`、`square`、`blurRadius`、`sobelThreshold`、`debug`、`debugDirectory`、`seamColor`、`seamShape`、batch directory/`recursive`/`concurrency`），新增 mode 冲突校验与 negative tests。
  - `CLIEntry.swift`：变薄，只负责解析→调用 processor→stdout 摘要→stderr 诊断与退出码。
  - `Package.swift`：`SeamCarvingCLI` 增加 `SeamCarvingApple` 依赖。
- **已知预留（未实现，属后续任务）：** `percentage`/`square` 已解析并校验，但 `CLIProcessor` 抛出 usage 错误（退出码 64）而非静默忽略；`blur`/`sobel`/`debug`/`seam`/batch 字段已类型化预留，engine 接线在 Task 2–5。
- **复审修复（`d796766`）：** 所有已解析但未实现的 reserved 选项（`--blur-radius`、`--sobel-threshold`、`--debug`、`--debug-directory`、`--seam-color`、`--seam-shape`、`--input-dir`、`--output-dir`、`--recursive`、`--concurrency`）在 `CLIProcessor.validateReservedOptions` 中显式拒绝（`CLIConfigurationError.reservedOptionNotImplemented`，退出码 64），不再静默忽略；补充 rejection tests 与 exit-code 测试；`--help` 更新为「Implemented / Reserved」两段；`CLIOptions` 恢复 `width`/`height` 兼容访问器（`Int?`，仅 `.exact` 模式非 nil）。
- **未改动：** 用户未提交的 `CODE_REVIEW.md`（保持未跟踪，未纳入提交）。

### Task 1 — 遗留问题（非阻塞，需后续处理）

1. **`width`/`height` 未真正保持 source compatibility。** 新增访问器为 `Int?`，原 API 为 `Int`，旧代码 `let width: Int = options.width` 仍会编译失败。当前只能称为“保留字段名称”。二选一：
   - 明确记录为公开 API breaking change；或
   - 保留旧 `Int` 语义，另增新的 `resizeMode` 配置接口。
   （建议在 Task 2 定义最终 `ResizeMode` 时一并决策并落实，避免二次破坏。）
2. **`CLIProcessor` 仍直接写 stderr。** 内部直接 `FileHandle.standardError.write(...)` 输出 progress，处理层仍耦合进程 I/O。建议在 Task 3（stdin/stdout binary mode）之前改为注入 progress sink，由 `CLIEntry` 负责输出。

### Task 2 — 已完成

- **提交：** `f0dc2cd` `feat: add scalar resize and energy controls`
- **验证：**
  - `swift test --package-path . --parallel` → 139/139 通过
  - `swift test --package-path . --filter 'CLIOptionsTests|CLIEndToEndTests' --parallel` → 通过
  - `xcodebuild -scheme SeamCarvingSwift-Package -workspace . -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` → BUILD SUCCEEDED
  - `git diff --check` 干净
- **改动摘要：**
  - `ResizeOptions` 新增 `blurRadius: Int = 0`、`sobelThreshold: Float = 0`。
  - `PixelSize.scaled(byPercentage:)`（源尺寸基准、round-half-away-from-zero、最小 1、允许 enlarge）与 `squareTarget()`（短边）。
  - `LuminancePlane.blurred(radius:)`：可分离 box blur（clamp-to-edge），CPU 与 Accelerate 共用以保证 bit 兼容。
  - `BackwardEnergy`/`AccelerateEnergy`：blur + Sobel threshold 进入实际 energy；零值复现默认结果。
  - `CoreResizeEngine`：forward energy + blur/threshold 抛 `invalidConfiguration`（不静默忽略）。
  - `MetalBackend`：blur/threshold 委托 CPU 参考后端（`effectiveIdentifier` 返回 `cpu-fallback`），不忽略参数。
  - CLI：`--percentage`/`--square` 解析并按源尺寸解出目标；`--blur-radius`（Int）/`--sobel-threshold` 接线进 `ResizeOptions`；`CLIProcessor` 移除对应 reserved 拒绝。
  - 移除 `CLIConfigurationError.reservedResizeModeNotImplemented`；`--help` 更新为 percentage/square/blur/sobel 已实现。
  - `docs/capability-matrix.md` 新增第 11、12 行并标记 verified。
- **语义约定：** percentage 以源尺寸为基准（`50`=一半），round half away from zero，每轴最小 1，`>100` enlarge；square 取短边为边长（不 enlarge）；blur/sobel 仅作用于 backward Sobel energy，配合 forward energy 时报错。
