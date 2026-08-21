# Seam Carving 的 Swift / iOS / macOS 实现调研与技术方案

> 状态：实现前技术调研
> 日期：2026-08-21
> 目标平台：iOS、macOS（核心库共用 Swift 代码）
> 参考论文：Avidan & Shamir, *Seam Carving for Content-Aware Image Resizing*（SIGGRAPH 2007）

## 1. 执行摘要

建议不要直接把参考仓库逐行翻译成 Swift，也不要一开始就把所有步骤写成 Metal。更稳妥的路线是：

1. 先做一个**纯 Swift、确定性、可测试的 CPU 参考实现**，作为所有优化后端的正确性基准。
2. 用 **Accelerate/vImage** 优化颜色转换、亮度图和 Sobel/卷积；是否用 vDSP 优化动态规划必须由基准测试决定。
3. 用 **Metal compute** 实现能量、掩码融合、seam 压紧/插入；在此基础上再实现完整 GPU 动态规划。
4. **Core Image** 负责输入输出、颜色管理和预览链，不负责 seam 的全局动态规划。
5. **Vision** 放在独立的可选 target 中：首发使用人脸矩形生成保护 mask；注意力/对象显著性图留作后续增强。Core 不接触 `VNFaceObservation` 或其他 Vision 类型。
6. **Core ML** 只用于可选的学习型显著性/语义保护图；**MLX Swift 不建议成为经典 seam carving 的生产核心依赖**。

推荐的生产形态是“同一算法语义、多个可替换后端”：
```text
public API / Apple image bridges
                │
          SeamCarvingCore
          ┌─────┼──────────┐
          │     │          │
       Swift  Accelerate  Metal
       CPU     CPU         GPU

optional SeamCarvingVision
        │ FaceRegion → protection Mask
        └───────────────────────> Core semantics
```

这里最重要的性能结论不是“Metal 一定更快”，而是：**能量计算和像素搬移非常适合 GPU；动态规划每一行依赖上一行，因此 GPU 的收益取决于图片尺寸、删除 seam 数量、command encoding、同步与内存往返成本。必须用端到端 benchmark 决定默认后端。**

---

## 2. 对参考 GitHub 仓库的审计

参考仓库：[msuv08/seam-carving](https://github.com/msuv08/seam-carving)。它是一个 2021 年的 MATLAB 教学实现，采用 MIT License；仓库 README 将其描述为 SIGGRAPH 2007 算法的 MATLAB 重实现，并列出 Sobel、动态规划、横纵 seam 与回溯等能力。

### 2.1 实际结构

| 文件 | 作用 |
|---|---|
| [`energy_calculator.m`](https://github.com/msuv08/seam-carving/blob/main/energy_calculator.m) | 灰度化，以 `[-1, 1]` 差分计算梯度幅值 |
| [`sobel_energy_calculator.m`](https://github.com/msuv08/seam-carving/blob/main/sobel_energy_calculator.m) | 3×3 Sobel 版本，但主流程没有调用它 |
| [`vert_min_energy_map.m`](https://github.com/msuv08/seam-carving/blob/main/vert_min_energy_map.m) | 逐行生成竖直累计能量图 |
| [`horiz_min_energy_map.m`](https://github.com/msuv08/seam-carving/blob/main/horiz_min_energy_map.m) | 逐列生成水平累计能量图 |
| [`vert_seam_finder.m`](https://github.com/msuv08/seam-carving/blob/main/vert_seam_finder.m) | 从最后一行回溯竖直 seam |
| [`horiz_seam_finder.m`](https://github.com/msuv08/seam-carving/blob/main/horiz_seam_finder.m) | 从最后一列回溯水平 seam |
| [`removeVertical.m`](https://github.com/msuv08/seam-carving/blob/main/removeVertical.m) | 每次重新计算能量和 seam，再逐行复制像素 |
| [`removeHorizontal.m`](https://github.com/msuv08/seam-carving/blob/main/removeHorizontal.m) | 水平版本 |
| [`reduce_img_size.m`](https://github.com/msuv08/seam-carving/blob/main/reduce_img_size.m) | 先缩宽、再缩高 |
| [`display_seams.m`](https://github.com/msuv08/seam-carving/blob/main/display_seams.m) | 尝试把 seam 标红用于展示 |

主流程实际使用的是一阶差分 `energy_calculator.m`，不是 README 所称的 Sobel 实现。算法只支持缩小，没有论文中的 seam 插入、对象移除 mask、保护区域、forward energy、多尺寸图像或宽高顺序优化。

### 2.2 不应直接移植的原因

该仓库适合帮助理解算法，但不适合作为生产实现的逐行移植基础：

- MATLAB 多次分配完整中间矩阵；每删除一条 seam 都重算整图并新建输出。
- 内部大量双精度矩阵，而 Apple 图像管线通常更适合明确的 `UInt8`/`Float32` 和固定 stride。
- 没有测试、benchmark、颜色空间、alpha、EXIF/UIImage orientation 或非连续 `rowBytes` 的语义。
- tie-break 没有规范，不同后端遇到相同代价时可能选择不同 seam。
- `display_seams.m` 每轮记录一条 seam 却调用 `removeVertical(..., 2)` / `removeHorizontal(..., 2)`，且没有把缩小后坐标映射回原图。
- `vert_min_energy_map.m` 的最右边界能量索引可疑：目标是最后一列，代码却读取 `energy_image(r, cols-1)`；移植前应以论文公式和测试重新实现，而不是复制这一逻辑。
- 水平 seam finder 的边界分支及注释存在不一致，进一步说明需要独立的 oracle 测试。

许可证为 [MIT](https://github.com/msuv08/seam-carving/blob/main/LICENSE)。若复制了有版权意义的实现代码，需要保留其版权声明和许可证；如果只是依据论文和数学公式独立重写，则仍应在文档中致谢并由项目方自行确认法律/专利要求。

### 2.3 Caire 的参考价值与移植边界

另一个值得审计的实现是 [esimov/caire](https://github.com/esimov/caire/tree/072a5888af55502d89b07157613be885cca14156)。本节固定到 caire commit `072a5888af55502d89b07157613be885cca14156`；该版本的 [`go.mod`](https://github.com/esimov/caire/blob/072a5888af55502d89b07157613be885cca14156/go.mod#L1-L15) 又固定使用 Pigo v1.4.5，对应 commit `9cf22eb3e79ee84931b718f2a2852500b5b0ad26`。固定引用很重要：下述结论描述的是这些源码版本，而不是会继续变化的分支头。

#### 2.3.1 值得借鉴的行为

Caire 比 MATLAB 参考仓库覆盖了更接近产品的路径：缩小与放大、宽高两个方向、protect/remove mask，以及在寻找 seam 前检测人脸并提高其能量。以下设计思想值得保留，但应重新定义为可测试的 Swift 语义：

- 人脸保护不是 DP 的特殊分支，而是先栅格化为保护区域，再进入统一能量管线。
- protect mask、removal mask 和 face region 都随当前图像尺寸、旋转和 seam edit 保持对齐。
- 若目标尺寸小于被保护人脸的检测尺度，及早报告无法满足“保持人脸不变”的约束，而不是静默产生明显变形。
- 人脸矩形写入 Sobel 图后再经过 blur，可形成比硬边矩形更平滑的保护 halo。
- 对大幅度缩放，先用 Lanczos 按比例接近目标，再只对剩余尺寸执行 seam carving，可显著减少 seam 次数；Caire 在 [`processor.go`](https://github.com/esimov/caire/blob/072a5888af55502d89b07157613be885cca14156/processor.go#L397-L436) 中也同步预缩放用户 masks。这是很有价值的产品性能模式，但会改变“全程 exact seam carving”的输出语义。

这些行为可直接从 caire 的 [`ComputeSeams`](https://github.com/esimov/caire/blob/072a5888af55502d89b07157613be885cca14156/carver.go#L77-L230)、[宽高旋转与 mask 同步](https://github.com/esimov/caire/blob/072a5888af55502d89b07157613be885cca14156/processor.go#L356-L388)，以及 [remove/insert seam 时同步编辑 mask](https://github.com/esimov/caire/blob/072a5888af55502d89b07157613be885cca14156/processor.go#L503-L572) 的源码确认。

不过，caire 的具体融合顺序也必须明确记录，不能只概括为“保护人脸”。该版本先把 protect mask 的白像素写成高能量，再把 removal mask 的白像素写成低能量，最后把通过阈值的人脸矩形写成白色，因此 face region 最终覆盖 removal mask；所有这些结果之后再统一 blur。Swift 实现若提供受 Caire 启发的策略，应把这个冲突优先级写进 policy 和测试，而不是依赖调用顺序偶然得到相同结果。

首发 API 仍以 exact sequential seam discovery 为唯一默认语义，暂不加入 Lanczos 预缩放，以免同一个选项在不同后端产生不可比较的结果。后续可以单独增加显式 opt-in 的 `.lanczosThenExactResidual` planner，并在 benchmark 和 golden corpus 中作为不同算法模式报告，不能静默放进 `.automatic`。

#### 2.3.2 为什么不能逐行翻译 Pigo 路径

Caire 使用 Pigo 的输出并不是通用的人脸检测抽象：

- Pigo [`Detection`](https://github.com/esimov/pigo/blob/9cf22eb3e79ee84931b718f2a2852500b5b0ad26/core/pigo.go#L193-L200) 返回 `Row`、`Col`、`Scale`、`Q`。前两项是当前左上原点栅格中的中心行/列，`Scale` 是正方形检测窗尺度。
- [`RunCascade`](https://github.com/esimov/pigo/blob/9cf22eb3e79ee84931b718f2a2852500b5b0ad26/core/pigo.go#L210-L258) 只保留原始级联分数 `Q > 0` 的窗口；[`ClusterDetections`](https://github.com/esimov/pigo/blob/9cf22eb3e79ee84931b718f2a2852500b5b0ad26/core/pigo.go#L260-L305) 对重叠窗口求平均位置和尺度，却把成员 `Q` 相加。因此 caire 的 `face.Q > 5` 是 Pigo 特定的聚类总分阈值，不是概率，也不能线性映射到 Vision confidence。
- Caire 最终保护框以中心为基准、半径取 `Scale / 1.7`，并不等于直接使用 Pigo 检测窗。把 Vision bounding box 再机械套用这个公式，会改变框的几何意义。
- Pigo 本身另有 pupil/landmark 能力，但 caire 的这条路径没有调用它；因此使用 Vision landmarks 应被视为新质量模式，而不是兼容移植。

Apple 的 [`VNDetectFaceRectanglesRequest`](https://developer.apple.com/documentation/vision/vndetectfacerectanglesrequest) 返回 `VNFaceObservation`。其 [`boundingBox`](https://developer.apple.com/documentation/vision/vndetectedobjectobservation/boundingbox) 相对处理后的图像尺寸归一化，并以左下角为原点；Vision observation 的 [`confidence`](https://developer.apple.com/documentation/vision/vnobservation/confidence) 通常归一化到 `[0, 1]`。因此适配器必须分别转换坐标、定义新的 confidence 阈值并校准扩框参数，不能复用 `Q > 5`。

若输入已经物理规范化为 upright、处理尺寸为 `W × H`，将 Vision 矩形 `b` 转成左上原点、半开像素矩形可采用：

```text
x0 = floor(b.minX * W)
x1 = ceil (b.maxX * W)
y0 = floor((1 - b.maxY) * H)
y1 = ceil ((1 - b.minY) * H)
```

结果还要 clamp 到图像边界。若没有先规范化方向，则这一组 y-flip 公式不够：`.left`、`.right` 及四种 mirrored orientation 需要完整的坐标变换，部分情况还会交换宽高。Apple 的 [still-image Vision 示例](https://developer.apple.com/documentation/vision/detecting-objects-in-still-images) 明确指出 `CGImage`、`CIImage` 和 `CVPixelBuffer` 不携带 orientation，必须在 request handler 初始化时另行提供；[`CGImagePropertyOrientation`](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation) 的 raw value 也不能与 `UIImage.Orientation` 直接互换。建议在进入 seam core 前把像素和用户 mask 一次性规范化到同一个 upright 坐标系，随后以 `.up` 调用 Vision。

Caire 的竖向路径会物理旋转图片，并在 `vRes` 时把 `FaceAngle` 强制设为 `0.2`。Pigo 定义 `0...1` 对应 `0...2π`，且旋转分类器使用 32 项查找表量化角度，见 [Pigo API 示例](https://github.com/esimov/pigo/blob/9cf22eb3e79ee84931b718f2a2852500b5b0ad26/README.md#L120-L132) 与 [`classifyRotatedRegion`](https://github.com/esimov/pigo/blob/9cf22eb3e79ee84931b718f2a2852500b5b0ad26/core/pigo.go#L149-L188)。这不是可以翻译成 Vision orientation 的元数据值；Vision 适配器应描述输入像素的真实方向，而不是复制 `0.2`。

#### 2.3.3 检测 cadence、异步与复现性

Caire 在每次 `shrink`/`enlarge` 中重新调用 `ComputeSeams`，也就是通常每编辑一条 seam 都在变形后的当前图像上重新检测人脸。逐 seam 重检最接近其现有行为，但会把检测成本乘以 seam 数量。更适合移动端的默认策略是初始检测一次、生成 face protection mask，之后像用户 mask 一样随每条 seam 做 remove/insert/rotate；两种 cadence 必须作为显式策略，不能作为隐藏的性能优化互换。

稳定的 Objective-C/Swift Vision API 通过 [`VNImageRequestHandler`](https://developer.apple.com/documentation/vision/vnimagerequesthandler) 执行请求；[`perform(_:)`](https://developer.apple.com/documentation/vision/vnimagerequesthandler/perform%28_%3A%29) 在所有请求完成或失败后才返回。它可以成为一次 seam 迭代中的同步点，但应在主线程之外执行，并由外层 `async throws` API 承载等待、取消和错误。若使用新版 async Vision API，也应保持相同的适配层语义，而不是让 seam core 依赖某一代请求 API。

Vision request 的算法版本同样属于结果语义。Apple 将 [`defaultRevision`](https://developer.apple.com/documentation/vision/vnrequest/defaultrevision) 定义为应用所链接 SDK 对应的最新 revision，并提供 [`supportedRevisions`](https://developer.apple.com/documentation/vision/vnrequest/supportedrevisions) 做运行时能力检查。因此生产配置应显式固定已验证且受当前系统支持的 [`revision`](https://developer.apple.com/documentation/vision/vnrequest/revision)，并在 benchmark/golden 记录中保存 OS build、设备和 revision。固定 revision 能避免无意跟随默认值变化，但 Apple 文档没有承诺不同 OS 与硬件上的 bit-exact 检测结果；Vision 回归应以 box/mask IoU、漏检率、误检率和最终 seam 是否穿过保护区域衡量，而不是要求与 Pigo 输出逐框相同。

Pigo 固定 cascade 和参数更容易建立确定性基线，但 caire 的 `detAttempts`、`isFaceDetected`、`sobel` 与 `energySeams` 是包级可变状态，见 [`carver.go`](https://github.com/esimov/caire/blob/072a5888af55502d89b07157613be885cca14156/carver.go#L20-L33)。这些状态不应被移植到 Swift 全局变量；每次 resize 应拥有独立 context，才能支持多图并发并避免前一次请求影响下一次请求。

#### 2.3.4 建议的 Swift 适配层与两种策略

Seam core 不应直接接收 `VNFaceObservation`。推荐把系统检测、坐标规范化、mask 栅格化和能量融合拆成四层：

```text
VisionFaceDetector
      │ implements
      ▼
FaceDetecting ──detect──> [FaceRegion]
                              │
                      FaceMaskRasterizer
                              │
                              ▼
                      Float protection mask
                              │
                       EnergyComposer
                              │
                              ▼
                       adjusted energy
```

概念接口如下；`FaceRegion.bounds` 始终使用当前 upright 栅格、左上原点、半开像素坐标，避免 Vision 坐标泄漏到 core：

```swift
public struct FaceRegion: Sendable, Equatable {
    public var bounds: PixelRect
    public var confidence: Float
    public var landmarks: [FaceFeature: [PixelPoint]]?
}

public protocol FaceDetecting {
    func detectFaces(inUpright image: CGImage) async throws -> [FaceRegion]
}

public struct CaireInspiredParameters: Sendable {
    public var minimumConfidence: Float
    public var expansionFraction: Float
    public var protectionWeight: Float
}

public struct VisionQualityParameters: Sendable {
    public var minimumConfidence: Float
    public var expansionFraction: Float
    public var featherFraction: Float
    public var protectionWeight: Float
}

public enum FaceProtectionPolicy: Sendable {
    case caireInspired(CaireInspiredParameters)
    case visionQuality(VisionQualityParameters)
}

public enum FaceDetectionCadence: Sendable {
    case detectOnceAndTransformMask
    case redetectEveryPass
}
```

`FaceDetecting` 只做检测与 canonical coordinate 转换，并在 detector 构造时固定 Vision revision；`FaceMaskRasterizer` 负责 confidence 过滤、矩形扩张、ellipse feather 与 clamp；`EnergyComposer` 统一实现 gradient、protect、removal、face 和 saliency 的权重及冲突规则。cadence 属于 `FaceAwareSeamCarver` 的编排配置，而不是 detector 属性。这样既能独立测试坐标与 mask，也能在不修改 DP 的前提下更换 Vision、测试桩或其他 detector。

建议公开两个有明确语义的 preset：

| 策略 | 检测与 mask | 目标 |
|---|---|---|
| `caireInspired` | face rectangles；face 覆盖 removal；confidence、扩框和有限保护权重为显式可校准参数；可选择逐 seam 重检；不声称复现 Caire blur | 借鉴 caire 的保护意图，但明确不承诺 Pigo/Caire 行为兼容 |
| `visionQuality` | 默认检测一次并随 seam 传播 mask；可用 [`VNDetectFaceLandmarksRequest`](https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest) 生成轮廓或凸包保护区 | 利用 Vision 信息改善保护质量和性能，不追求 caire 行为兼容 |

两种策略都需要在人脸大小、旋转、镜像、多人、遮挡、透明输入以及 protect/removal 冲突样例上测试。性能报告应把 detect、坐标转换、mask rasterize/blur 和 seam pipeline 分开计时，避免把 Vision 固定成本误归因于 DP 后端。

最后，caire 和 Pigo 都采用 MIT License，见固定版本的 [caire LICENSE](https://github.com/esimov/caire/blob/072a5888af55502d89b07157613be885cca14156/LICENSE) 与 [Pigo LICENSE](https://github.com/esimov/pigo/blob/9cf22eb3e79ee84931b718f2a2852500b5b0ad26/LICENSE)。若复制或改编其具有版权意义的源码、测试、示例或二进制分类器，应在分发物中保留相应版权声明与许可证文本，并清楚记录来源与修改；仅参考行为后独立实现也应保留技术致谢。是否构成衍生作品及产品所需 notices 应由项目方按实际采用内容审查，不能因改写为 Swift 就省略许可证义务。

---

## 3. 产品范围与算法语义

### 3.1 首个发布版本应支持

- 竖直和水平 seam；宽高缩小与放大。
- backward Sobel 与 forward-luma energy。
- protect/remove mask、对象移除，以及 mask 与 seam 的同步编辑。
- `RGBA8Image` Core API 与 `CGImage`、`CIImage`、`CVPixelBuffer` Apple 桥接；UIKit/AppKit 仅作为薄桥接。
- 确定的边界策略和 tie-break。
- 纯 Swift CPU、Accelerate 与显式 opt-in Metal 后端，以及后端一致性测试。
- 异步执行、取消和进度回调，不阻塞主线程。
- 可选 `SeamCarvingVision` 人脸保护：显式 request revision、upright canonical 坐标、两种策略与两种检测 cadence。

### 3.2 后续能力

- Vision 注意力/对象显著性图与 Core ML 自定义语义保护图。
- `MTLTexture` 高级入口和视频时序一致性。
- 近似批处理、transport map、局部能量更新等明确改变复杂度或算法语义的优化。
- HDR/extended-range 保真管线；首发明确拒绝这类输入，不做隐式 clamp 或 tone mapping。

### 3.3 必须先固定的语义

所有后端必须共享以下定义，否则“CPU/GPU 一致性”没有意义：

- 输入像素方向、颜色空间与 alpha 是否预乘。
- 能量是在 sRGB 编码值还是 linear sRGB 上计算。
- Sobel 的梯度范数是 `abs(gx)+abs(gy)` 还是 `sqrt(gx²+gy²)`。
- 图像边界是 clamp、mirror 还是 zero padding。
- 候选代价相同时选择左、中还是右。
- protect/remove mask 的组合、权重、冲突优先级。
- 插入像素的颜色插值和多个 seam 的坐标修正规则。

建议默认：规范方向后的 RGBA8、linear-sRGB 亮度、Float32 能量、clamp-to-edge、相同代价优先 predecessor 的较小 x。

---

## 4. Apple 框架选型

| 框架 | 推荐用途 | 优势 | 不适合/风险 | 结论 |
|---|---|---|---|---|
| 纯 Swift | 参考 DP、回溯、测试 oracle、小图 | 易验证、无额外依赖 | 大图多 seam 可能慢 | 必须保留 |
| Accelerate/vImage | 格式转换、灰度、卷积、CPU fallback | Apple 针对 CPU 向量单元优化，CG/CV 桥接成熟 | 非规则 seam 压紧没有现成 API | 推荐 |
| Accelerate/vDSP | Float 向量 min/add/argmin 实验 | API 成熟 | 多个短调用和临时 buffer 可能比紧凑 Swift loop 更慢 | benchmark 后采用 |
| Metal compute | 能量、mask、DP、argmin、回溯、像素 gather | 可让数据常驻 GPU；像素级操作高度并行 | DP 有逐行依赖；同步与编码复杂 | 主要高性能后端 |
| Metal Performance Shaders | Sobel/卷积等标准 GPU filter | 系统优化实现 | 没有 seam DP 原语 | 与自写 Sobel 二选一实测 |
| Core Image | CIImage 链、颜色管理、显示/导出 | 惰性求值并能合并普通 filter | 不适合全局 DP；processor kernel 会阻断部分融合 | 只做桥接/前后处理 |
| Vision | 注意力/对象显著性保护图 | Apple 原生语义显著性 | 有额外延迟，且结果受系统 revision 影响 | 可选质量增强 |
| Core ML | 自定义显著性/分割模型 | 系统调度 CPU/GPU/ANE | 经典 DP 不应包装成模型 | 可选 learned energy |
| MLX Swift | 数组/学习型实验 | lazy arrays、CPU/GPU、统一内存 | 0.x、部署要求更高、包和编译复杂；不擅长 irregular DP | 不作为核心依赖 |

Apple 将 [Accelerate](https://developer.apple.com/documentation/accelerate) 定位为高性能、低能耗的 CPU 数学与图像计算框架；[vImage](https://developer.apple.com/documentation/accelerate/vimage-library) 明确利用 CPU 向量处理能力，并提供 Core Graphics/Core Video 互操作。Apple 也提醒 planar 与 interleaved 布局需要对具体负载实测，而不是假设某一种总是更快：[vImage 图像性能优化](https://developer.apple.com/documentation/accelerate/optimizing-image-processing-performance)。

[Metal compute](https://developer.apple.com/documentation/metal/performing-calculations-on-a-gpu) 通过 command queue、command buffer、compute encoder 与线程网格执行 GPU 计算；线程组大小应读取 pipeline 的能力，而不是写死，参见 [Calculating threadgroup and grid sizes](https://developer.apple.com/documentation/metal/calculating-threadgroup-and-grid-sizes)。专用的 [`MPSImageSobel`](https://developer.apple.com/documentation/metalperformanceshaders/mpsimagesobel)、[`MPSImageConvolution`](https://developer.apple.com/documentation/metalperformanceshaders/mpsimageconvolution) 和 [MPS image filters](https://developer.apple.com/documentation/metalperformanceshaders/image-filters) 可用于 Sobel/卷积，但剩余 seam 算法仍需自定义 kernel。使用 MPS 时仍须把灰度转换、边界和梯度范数与 CPU oracle 对齐。

Core Image 的普通滤镜可以由框架重排和合并，但 [`CIImageProcessorKernel`](https://developer.apple.com/documentation/coreimage/ciimageprocessorkernel) 无法享受同样的跨 kernel 合并；因此它只应在算法不能由 CIKernel 表达时作为 Metal/vImage 接口。[Core Image custom kernels](https://developer.apple.com/documentation/coreimage/writing-custom-kernels) 适合逐像素滤波，不适合带全局依赖的 seam DP。

截至本次审计日期，MLX Swift 主分支的 [`Package.swift`](https://github.com/ml-explore/mlx-swift/blob/main/Package.swift) 声明 macOS 14、iOS 17、tvOS 17 和 visionOS 1，并使用 Metal/Accelerate；`main` 会变化，生产项目必须固定经过验证的 tag/commit，并同时记录所需 Swift tools 与 Xcode 版本。它适合实验，但会把核心库的部署版本、构建链和依赖面一起抬高。除非 benchmark 证明收益，经典 seam carving 没有必要为数组抽象、自动微分或 ML 生态支付这些成本。

除 MLX 上述当前声明外，本文不为其他框架给出“一刀切”的最低系统版本：Metal、MPS、Core Image Metal API、Vision 和 Core ML 内部不同 symbol 的 availability 并不相同。实现时应以实际调用的每个 symbol 为准设置 deployment target、`@available` 与运行时 capability check，而不是根据框架整体首次出现的版本推断。

### 4.1 Vision 比 MLX 更直接的“内容感知”增强

原始梯度能量不真正理解人脸或物体。Apple Vision 的 [`VNGenerateAttentionBasedSaliencyImageRequest`](https://developer.apple.com/documentation/vision/vngenerateattentionbasedsaliencyimagerequest) 会生成可能吸引注意力区域的热图；[`VNGenerateObjectnessBasedSaliencyImageRequest`](https://developer.apple.com/documentation/vision/vngenerateobjectnessbasedsaliencyimagerequest) 生成对象显著性热图。可把它们缩放到能量图尺寸并融合：

```text
adjustedEnergy = gradientEnergy
               + saliencyWeight * saliency
               + protectWeight  * protectMask
               - removalWeight  * removalMask
```

这应当是可选策略，因为 Vision 推理有固定开销，其 revision 变化也可能影响结果复现。为了可复现，应固定支持的 request revision，并向 Vision 与 seam-carving bridge 传入同一 EXIF orientation；新版 Swift-native Vision API 还需做 availability gate，广部署版本可继续使用稳定的 `VN...Request` API。

---

## 5. 建议的 Swift Package 架构

```text
SeamCarvingSwift/
├── Package.swift
├── Sources/
│   ├── SeamCarvingCore/
│   │   ├── ImageBuffer.swift
│   │   ├── Energy.swift
│   │   ├── DynamicProgramming.swift
│   │   ├── SeamPath.swift
│   │   ├── SeamEdit.swift
│   │   ├── Masks.swift
│   │   ├── ResizePlanner.swift
│   │   └── CPUReferenceBackend.swift
│   ├── SeamCarvingAccelerate/
│   │   ├── VImageBridge.swift
│   │   └── AccelerateEnergy.swift
│   ├── SeamCarvingMetal/
│   │   ├── MetalBackend.swift
│   │   ├── MetalResources.swift
│   │   ├── PipelineCache.swift
│   │   └── Shaders/
│   │       ├── Luminance.metal
│   │       ├── Energy.metal
│   │       ├── DynamicProgramming.metal
│   │       ├── Reduction.metal
│   │       ├── Backtrack.metal
│   │       └── SeamEdit.metal
│   ├── SeamCarvingApple/
│   │   ├── CGImageBridge.swift
│   │   ├── CIImageBridge.swift
│   │   ├── CVPixelBufferBridge.swift
│   │   ├── UIImageBridge.swift
│   │   └── NSImageBridge.swift
│   ├── SeamCarvingVision/
│   │   ├── FaceDetecting.swift
│   │   ├── VisionFaceDetector.swift
│   │   ├── FaceMaskRasterizer.swift
│   │   └── FaceAwareSeamCarver.swift
│   └── seamcarve-cli/
├── Tests/
│   ├── SeamCarvingCoreTests/
│   ├── SeamCarvingBackendParityTests/
│   ├── SeamCarvingAppleTests/
│   └── SeamCarvingVisionTests/
└── Benchmarks/
```

`SeamCarvingCore` 尽量只依赖 Foundation。UIKit/AppKit 通过条件编译隔离；Metal、Accelerate 和 Vision 分别位于独立 target，避免 CPU-only 使用者承担不必要依赖。`SeamCarvingVision` 把检测结果转换为普通 Core mask，而不是把 Vision 类型传入 Core。

### 5.1 公共 API 草案

```swift
public struct SeamCarver: Sendable {
    public init()
    @_spi(Backend) public init(backend: any SeamCarvingBackend)

    public func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> RGBA8Image
}

public struct AppleSeamCarver: Sendable {
    public init(configuration: AppleSeamCarverConfiguration = .init()) throws

    public func resize(
        _ image: CGImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CGImage
}

public struct AppleSeamCarverConfiguration: Sendable {
    public var backend: BackendPreference   // automatic/cpu/accelerate/metal
    public var metalMode: MetalExecutionMode
    public var deterministic: Bool
}

public struct ResizeOptions: Sendable {
    public var energyMode: EnergyMode
    public var dimensionOrder: DimensionOrder
    public var masks: MaskPair
    public var progress: (@Sendable (ResizeProgress) -> Void)?
}

public struct MaskPair: Sendable {
    public let protectionLayers: [ProtectionLayer]
    public let removal: Mask?
    public let removalWeight: Float
}

public struct ProtectionLayer: Sendable {
    public let mask: Mask
    public let strength: MaskStrength       // soft(finiteNonnegative) / hard
}
```

后端扩展协议使用 `@_spi(Backend)`，普通调用者通过无参数 `SeamCarver()` 获得 CPU 实现；不要在稳定 v1 API 中暴露 `MTLTexture`/`vImage_Buffer` 等实现细节。多个 protection layer 独立保留各自 soft/hard 强度，避免 face policy 意外升级或削弱用户保护层。`FaceAwareSeamCarver` 位于可选 Vision target，通过组合 `AppleSeamCarver` 和 Core masks 工作，不改变上述 Core API。

---

## 6. CPU 参考实现

### 6.1 数据布局

- 输入/输出：RGBA8 或 BGRA8，明确 `rowBytes`。
- 能量和累计代价：`Float32`。
- DP 只保留 previous/current 两行累计代价。
- parent direction：每像素一个 `Int8`（`-1/0/+1`）。
- seam 与 insertion index map：每个坐标使用 `UInt32`；parent direction 独立使用 `Int8`（`-1/0/+1`）。

不要在 `Array<Pixel>` 和 `UIImage` 之间反复转换。裸内存由一个 RAII storage 对象持有，所有指针访问限定在 `withUnsafeBytes` 生命周期内。

### 6.2 确定性 DP

```swift
previous[x] = energy[x]

for y in 1..<height {
    for x in 0..<width {
        let leftX = max(0, x - 1)
        let rightX = min(width - 1, x + 1)
        let (cost, predecessor) = stableMinimum(
            (previous[leftX], leftX),
            (previous[x], x),
            (previous[rightX], rightX)
        )
        current[x] = energy[y * width + x] + cost
        parent[y * width + x] = Int8(predecessor - x)
    }
    swap(&previous, &current)
}
```

`stableMinimum` 必须显式规定相等时的选择顺序。回溯从最后一行稳定 argmin 开始，复杂度为：

- 一条 seam 时间：`O(width × height)`。
- 累计行空间：`O(width)`。
- parent 空间：`O(width × height)`。

删除一条竖直 seam 时，每一行用两段连续复制通常比逐像素 Swift append 更高效。水平 seam 可以先 transpose 后复用竖直算法；是否保留专用水平 kernel 由 benchmark 决定。

### 6.3 Forward energy

建议在 backward Sobel 完成后增加 forward energy，它估计删除后新邻接边带来的代价：

```text
CU = |I(x+1,y) - I(x-1,y)|
CL = CU + |I(x,y-1) - I(x-1,y)|
CR = CU + |I(x,y-1) - I(x+1,y)|

M(x,y) = min(
  M(x-1,y-1) + CL,
  M(x,  y-1) + CU,
  M(x+1,y-1) + CR
)
```

API 必须说明 `.forward` 是纯 disruption cost，还是 backward energy 与 forward cost 的混合，不能让不同后端自行解释。

---

## 7. Metal 后端设计

### 7.1 完整 GPU pipeline

```text
CGImage / CVPixelBuffer
  ↓ bridge/upload
RGBA8 MTLTexture
  ↓ luminance kernel
R32Float luminance
  ↓ Sobel or forward-cost kernel
R32Float energy
  ↓ apply mask/saliency
adjusted energy
  ↓ row-wise DP dispatches
two cumulative row buffers + Int8 parent buffer
  ↓ final-row argmin reduction
bottom x
  ↓ one-thread backtrack
seam[UInt32, height]
  ↓ gather remove/insert kernel
new RGBA texture + transformed masks
```

推荐资源：

- 颜色图像用 `MTLTexture`。
- DP 行、parent 和 seam 用 `MTLBuffer`。
- 累计代价坚持 Float32；FP16 随高度累加容易损失排序稳定性。
- 为最大图片尺寸预分配 ping-pong 资源并维护 `activeWidth/activeHeight`，避免每条 seam 重建所有资源。
- pipeline state、device、queue 缓存；每次请求拥有独立 scratch/context。

### 7.2 动态规划的 GPU 难点

同一行的所有 x 可以并行，但 `row y` 必须等待完整的 `row y-1`：

```metal
kernel void dpRow(
    device const float *previous,
    device float *current,
    device const float *energy,
    device char *parent,
    constant Params &p,
    uint x [[thread_position_in_grid]]) {
    if (x >= p.activeWidth) return;

    float left   = previous[max(int(x) - 1, 0)];
    float center = previous[x];
    float right  = previous[min(x + 1, p.activeWidth - 1)];
    Candidate best = stableMin(left, center, right);
    current[x] = energy[p.row * p.stride + x] + best.cost;
    parent[p.row * p.parentStride + x] = best.direction;
}
```

`threadgroup_barrier` 只能同步一个 threadgroup，不能充当整行所有 threadgroup 的全局 barrier。当宽度超过单个 threadgroup 可容纳线程数时，通用正确方案是为每一行编码依序 dispatch，并使用正确的资源同步。第一版使用 `MTLDevice` 直接创建、默认 tracked 的资源，让 Metal 跟踪冲突；若后续改用默认 untracked 的 heap 资源，则必须显式同步。memory barrier 用于同一 pass/encoder 内的可见性，fence/event 用于相应的跨 pass/queue 边界，不能互换概念。Apple 的 [Compute passes](https://developer.apple.com/documentation/metal/compute-passes) 也说明 encoder 的并行计算、资源 hazard 与线程安全边界。

因此第一版不应使用复杂的 persistent kernel 或 diagonal scan。建议依次验证：

1. **Metal energy + CPU DP + Metal gather** 的 hybrid。
2. 同一 command buffer 内逐行 dispatch 的完整 GPU DP。
3. GPU final-row reduction。
4. 单 GPU 线程回溯，避免把整个 parent map 读回 CPU。

一线程回溯的 GPU 利用率很低，但能避免 `W×H` parent 数据回读；如果后续 gather 仍在 GPU，seam 甚至无需回 CPU。

### 7.3 内存与同步

Apple silicon 默认可使用 CPU/GPU 都能访问的 shared storage；Apple 说明资源 storage mode 会随硬件变化，建议优先使用系统默认并用 `supportsFamily` 检查能力：[Setting resource storage modes](https://developer.apple.com/documentation/metal/setting-resource-storage-modes)。GPU-only 中间资源可测试 `.private`；Intel/独显 Mac 的 managed/private 语义和同步成本不同，不能把 iPhone/Mac Apple silicon 的结论直接套用。

尽量把一次或多次 seam 操作编码到较少 command buffers，避免每行 CPU/GPU 往返。Apple 的 command-buffer 最佳实践建议在不使 GPU 空闲的前提下减少提交数量：[Metal Command Buffers](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/CommandBuffers.html)。

Camera/video 输入可用 [`CVMetalTextureCache`](https://developer.apple.com/documentation/corevideo/cvmetaltexturecache-q3j) 把兼容的 `CVPixelBuffer` 映射成 Metal texture；这可以减少复制，但能否真正零拷贝取决于 pixel format、生产者和 storage，API 不应无条件承诺“zero copy”。

---

## 8. 多 seam、插入与宽高顺序

### 8.1 精确模式与近似模式必须分开

经典精确缩小是：

```text
find seam → remove → recompute → find next seam
```

在同一张能量图上一次找 k 条路径，不等价于连续 seam carving。可提供 `.approximateBatch(size:)`，但不能作为 `.exact` 的无声优化。

### 8.2 精确发现、合并像素搬移

可在临时图上逐次精确删除，并维护当前坐标到原图坐标的 `indexMap`；记录 k 条 seam 后，最终对原图一次 gather。这样不改变 seam 发现语义，只减少输出像素搬移次数，代价是额外 index map 内存。

### 8.3 放大

插入 k 条 seam 时，先在副本上逐次删除并记录到原图坐标，再在原图中排序、修正 offset 并一次插入，避免不断重复最低的一条 seam。插值应在规定的颜色和 alpha 语义中执行。

### 8.4 同时改宽高

至少提供：

- `.widthThenHeight`
- `.heightThenWidth`
- `.adaptiveNormalizedCost`

自适应模式可比较 `verticalCost / height` 与 `horizontalCost / width`，但它只是 heuristic，不等价于论文中的完整 transport map。完整 transport map 的状态和内存成本高，适合作为研究选项而非默认。

---

## 9. Apple 图像桥接注意事项

- `CGImage` 以像素尺寸为准，并固定 color space、bitmap info 和 alpha。
- `UIImage.imageOrientation` 不是已经旋转的像素；算法和 mask 前必须规范化。
- `NSImage.size` 是 point，且可能包含多个 representation；必须选择确定的 pixel representation。
- `CIImage` 是 lazy graph，extent 可能不从 `(0,0)` 开始；缓存 `CIContext`，规范 orientation/extent 后再进入算法。
- HDR/extended-range 输入不能悄悄夹到 8-bit；v1 可明确拒绝或转换，v2 再提供 Float16/HDR policy。
- public API 使用 pixel size，避免 UIKit/AppKit point/scale 歧义。

---

## 10. 并发、取消和错误处理

- 对单张图，seam 删除迭代有严格依赖，不应并行删除多条 exact seams。
- 多张独立图片可用 Swift structured concurrency 并行；不要为每个像素创建 Task。
- `MTLComputeCommandEncoder` 不跨请求共享；device、pipeline cache 与 command queue 可集中管理。
- GPU 工作通过 completion handler/continuation 接回 `async`，不要在主线程 `waitUntilCompleted()`。
- 在 seam 边界及 command buffer 完成点检查取消；长批次分段提交，平衡取消响应和提交开销。
- 错误类型至少区分：无 Metal 设备、资源分配失败、无可行 seam、mask 尺寸不匹配、目标尺寸非法、GPU 执行失败和取消。

---

## 11. 正确性测试

### 11.1 单元测试

1. 手工 3×3、4×4 能量矩阵与累计代价。
2. 左右边界 predecessor。
3. 全等代价时固定 tie-break。
4. `abs(seam[y] - seam[y-1]) <= 1`。
5. 删除后尺寸和幸存像素顺序。
6. horizontal 与 transpose + vertical 等价。
7. forward energy 手算样例。
8. protect/remove mask 冲突及 hard protect 无路径。
9. 插入多个 seam 的 offset。
10. 1 像素宽/高、透明图、非紧凑 stride、orientation 与颜色空间。

### 11.2 后端一致性

- CPU reference 是 oracle。
- 对人工整数能量矩阵，要求 seam 完全一致。
- 对浮点图像能量，比较 tolerance、合法性和总代价；近乎相等的路径不必强制像素级相同。
- GPU 测试开启 Metal API Validation；用不是 threadgroup 整数倍的尺寸检查越界。
- golden images 只作为补充，不能替代能量、路径和幸存像素的结构化断言。

---

## 12. Benchmark 与性能验收

测试矩阵：

```text
尺寸：256²、1080p、4K、超宽/超高
删除：1、8、32、宽度的 10%/25%
能量：backward、forward
mask：无 / protect / removal / Vision face protection
后端：Swift CPU、Accelerate、Metal hybrid、Metal full
设备：至少一台 iPhone/iPad 真机与一台 Apple silicon Mac
```

分别记录：decode/bridge、energy、mask、DP、argmin/backtrack、edit、command encoding、GPU wait、端到端时间、峰值 scratch memory 和能耗。Release 构建，预热 pipeline，报告 p50/p95；GPU 计时必须等待完成。XCTest 可记录 wall-clock、CPU、memory 与 signpost 指标：[Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests)。Metal 使用 Xcode GPU capture、timeline 与 counters 定位 occupancy、bandwidth 和 shader bottleneck：[Optimizing GPU performance](https://developer.apple.com/documentation/xcode/optimizing-gpu-performance/)。

`.automatic` 的阈值必须来自同一算法语义下的实测，不可简单写成“有 Metal 就用 Metal”。例如，小图或只删一条 seam 可能 CPU 更快，而大图、连续多 seam 且全程驻留 GPU 时 Metal 更有优势——这是需要验证的假设，不是预设结论。

---

## 13. 实施路线图

### M0：语义规范

- 固定颜色、alpha、边界、tie-break、mask 和插入定义。
- 建立人工能量矩阵与 expected seam 测试。

### M1：CPU correctness MVP

- 纯 Swift backward energy、DP、backtrack、remove。
- transpose 支持水平 seam。
- CGImage bridge 与 CLI。

### M2：算法完整性

- forward energy、protect/remove mask、对象移除。
- seam insertion、index mapping、宽高策略。
- 属性测试和 golden corpus。

### M3：Accelerate 后端

- vImage 格式转换、luma/Sobel 与 buffer 复用。
- 对比 Swift loop、vDSP 与 vImage 的阶段和端到端性能。

### M4：Metal hybrid

- Metal/MPS energy、mask、remove/insert。
- DP/backtrack 暂留 CPU，测量 readback/sync 成本。

### M5：完整 Metal

- 逐行 DP、parent、argmin、GPU backtrack。
- 全 GPU resident 的连续 seam pipeline。
- 跨设备 parity、Metal validation 和 CPU fallback。

### M6：优化与产品化

- 精确批量坐标映射、scratch pool/heap、可选局部 energy 更新。
- 可选 Vision face adapter、固定 revision、两种 mask 策略与检测 cadence。
- UIKit/AppKit/CIImage/CVPixelBuffer API、DocC、示例 App。
- 根据 benchmark 校准 `.automatic`。

---

## 14. 主要风险与决策检查点

| 风险 | 缓解方式 |
|---|---|
| 把 threadgroup barrier 当全网格 barrier | 通用 DP 使用逐行 dispatch；Metal validation + 宽图测试 |
| GPU/CPU 往返抵消收益 | 保持 texture/buffer 常驻 GPU，分阶段 benchmark |
| 多 seam “批量优化”改变算法 | API 区分 exact 与 approximate |
| 不同后端浮点/tie 产生不同 seam | 固定 tie-break，Float32 累计，容差和代价测试 |
| 色彩、方向、alpha 导致能量错误 | 统一桥接策略，针对 UIImage/NSImage/CIImage 测试 |
| 4K 中间资源峰值高 | 两行 cost、Int8 parent、scratch reuse；记录峰值内存 |
| Vision/MLX/Core ML 增加部署和包复杂度 | 全部做可选 provider/实验 target，不污染 Core |
| 参考仓库存在边界或展示逻辑问题 | 独立依据论文实现，以 CPU oracle 和手算测试验证 |

进入 M4 前的检查点：Accelerate 端到端瓶颈是否确实在 energy/edit？进入 M5 前的检查点：hybrid 的回读是否成为主要瓶颈，GPU DP 的逐行 dispatch 是否有现实收益？引入 MLX 前的检查点：它是否在目标真机上显著优于 Metal/Accelerate，并值得提高最低系统与依赖复杂度？

---

## 15. 最终建议

首个可发布版本建议选择：

```text
Swift CPU reference
+ Accelerate/vImage energy and conversion
+ optional Metal energy/edit backend
+ Core Image/CGImage bridges
+ optional Vision face protection adapter
```

随后用真实 iPhone 与 Apple silicon Mac 的数据决定是否让完整 Metal DP 成为默认。MLX Swift 可保留为研究 target，用于学习型 energy 或数组实验，但不应在没有性能证据时进入基础包。

这一路线同时满足：

- 正确性可验证；
- iOS/macOS API 共用；
- 能逐步获得 Apple silicon/GPU 性能收益；
- 不因某个高层框架锁死部署版本；
- 将算法质量增强（Vision/Core ML）与经典 seam-carving 核心解耦。

## 16. 主要资料

- [原论文出版信息与摘要](https://cris.tau.ac.il/en/publications/seam-carving-for-content-aware-image-resizing-2/)
- [参考 MATLAB 仓库](https://github.com/msuv08/seam-carving)
- [Caire 固定审计版本](https://github.com/esimov/caire/tree/072a5888af55502d89b07157613be885cca14156)
- [Pigo v1.4.5 固定源码版本](https://github.com/esimov/pigo/tree/9cf22eb3e79ee84931b718f2a2852500b5b0ad26)
- [Apple Accelerate](https://developer.apple.com/documentation/accelerate)
- [Apple vImage](https://developer.apple.com/documentation/accelerate/vimage-library)
- [Metal: Performing calculations on a GPU](https://developer.apple.com/documentation/metal/performing-calculations-on-a-gpu)
- [Metal compute passes](https://developer.apple.com/documentation/metal/compute-passes)
- [Metal threadgroup/grid sizing](https://developer.apple.com/documentation/metal/calculating-threadgroup-and-grid-sizes)
- [Metal Performance Shaders image filters](https://developer.apple.com/documentation/metalperformanceshaders/image-filters)
- [Core Image custom kernels](https://developer.apple.com/documentation/coreimage/writing-custom-kernels)
- [Core Image processor kernel](https://developer.apple.com/documentation/coreimage/ciimageprocessorkernel)
- [Vision attention saliency](https://developer.apple.com/documentation/vision/vngenerateattentionbasedsaliencyimagerequest)
- [Vision objectness saliency](https://developer.apple.com/documentation/vision/vngenerateobjectnessbasedsaliencyimagerequest)
- [Vision face rectangles](https://developer.apple.com/documentation/vision/vndetectfacerectanglesrequest)
- [Vision face landmarks](https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest)
- [ImageIO orientation](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation)
- [Core ML](https://developer.apple.com/documentation/coreml)
- [MLX Swift Package](https://github.com/ml-explore/mlx-swift/blob/main/Package.swift)
- [CVMetalTextureCache](https://developer.apple.com/documentation/corevideo/cvmetaltexturecache-q3j)
- [XCTest performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests)
- [Xcode Metal GPU performance](https://developer.apple.com/documentation/xcode/optimizing-gpu-performance/)
