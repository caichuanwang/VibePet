## Context

VibePet 是 macOS 14+ 桌面宠物应用（Swift 6.x，纯原生）。M0 已交付工程骨架、Bridge 归一化模型、socket 基础设施与 `ConfigStore`（`activeGeneratorID` 字段已在 `AppConfig` 中预留，默认 `local-cutout`）。

M1 在 `VibePetCore` 内补齐**生成管线**：把一张照片离线抠成带透明通道的精灵 PNG、持久化到 `pets/<uuid>/`，并通过配置驱动的 `GenerationService` 对外暴露单一入口。本里程碑完全脱离 UI（不 import AppKit/SwiftUI），只产出可被 M2 导入面板与宠物视图消费的 core 能力与素材。

参考资料：技术方案 §2（生成管线）、§6（pets 目录与 `PetAssetStore`）、§8.2（离线质量基准）；任务拆解 M1-1 ~ M1-5；版权边界 §11（clean-room）。

## Goals / Non-Goals

**Goals:**

- `PetGenerator` 协议与 `PetAsset`/`PetKind`/`PetLayer`/`GenError` 模型就位，`PetAsset` 编解码往返单测全绿。
- `LocalCutoutGenerator` 用 Vision `VNGenerateForegroundInstanceMaskRequest` 本地抠图：多主体取最大、裁到主体范围、输出带 alpha 的 PNG、驱动 `progress`、无主体抛 `GenError.noSubject`。
- `PetAssetStore` 把精灵写入 `pets/<uuid>/sprite.png` + `meta.json`，支持按 id 读/列举/删除，互不干扰。
- `GenerationService` 据 `config.activeGeneratorID` 路由生成器，对外只暴露 `generate(from:)`；未知 id 有确定行为。
- 离线基准脚本对 20 张带标签照片集跑 `LocalCutoutGenerator`，输出 P50/P95 与按标签可用率，可判定抠图 KPI。

**Non-Goals:**

- 不实现云端风格化/3D 生成器（`CloudStylizeGenerator`/`ThreeDGenerator` 仅作类型占位，属 v1.1/v2.0）。
- 不实现任何宠物窗、动画、导入 UI、棋盘格预览（属 M2）。
- 不实现分层动画素材的自动拆分（`PetLayer` 结构就位但 MVP 输出 `layers == []`）。
- 不接 Bridge/hook 链路（属 M3+）。
- 基准照片集的人工边缘打分是人工步骤，脚本只产出可打分的结果，不自动判主观质量。

## Decisions

### D1：生成抽象与 `PetAsset` 全部放 `VibePetCore/Generation`，UI 无关

- **选择**：`PetGenerator`/`PetAsset`/`PetKind`/`PetLayer`/`GenError` 放 `VibePetCore`，不 import AppKit/SwiftUI；输入用 `CGImage`，输出 `PetAsset`。
- **理由**：core 需被 CLI 复用、单测无 UI 依赖（沿用 M0 D4）。`CGImage`/CoreGraphics 是 UI 无关的图像基元。
- **替代**：用 `NSImage` 作输入/输出——把 AppKit 拉进 core，放弃；由 M2 在 UI 边界把 `NSImage`/拖入文件转 `CGImage` 再调 service。

### D2：`PetAsset.boundingInset` 不用 SwiftUI `EdgeInsets`

- **选择**：技术方案 §2 把 `boundingInset` 写作 `EdgeInsets`（SwiftUI 类型）。M1 改用 UI 无关类型——自定义 `struct PetEdgeInsets { top/leading/bottom/trailing: Double }`（或 `CGRect` 表达主体框）。
- **理由**：与 M0 D4 一致，避免 SwiftUI 进入 core；`Codable` 形态可控、便于 `meta.json` 固化。
- **替代**：直接用 `SwiftUI.EdgeInsets`——破坏 core 的 UI 无关性且其 `Codable` 形态不稳定，放弃。

### D3：抠图用 Vision 前景实例蒙版，`largestInstance` 取最大主体

- **选择**：`VNGenerateForegroundInstanceMaskRequest` → 取结果；多实例时按蒙版像素数/外接框面积排序取最大；`generateMaskedImage(ofInstances:from:croppedToInstancesExtent:true)` 得裁切后带 alpha 的图。
- **理由**：全程本地跑 Neural Engine、不联网（§2.1）；`croppedToInstancesExtent` 省手工 trim。
- **替代**：阈值抠图/手写分割——质量差、维护成本高，放弃。多主体点选/合成排入后续版本。
- **失败语义**：`request.results` 为空或无可用实例 → `GenError.noSubject`，由 M2 UI 提示换图/重试；失败路径**不**落任何半成品文件（§7）。

### D4：PNG 编码与 alpha 保真走 ImageIO/CoreGraphics

- **选择**：用 `CGImageDestination`（UTType `.png`）把 masked `CGImage` 写盘，确保保留 alpha；后处理裁切空白与归一化尺寸在写盘前完成。
- **理由**：ImageIO 是写 PNG 的原生稳定路径，能精确控制 alpha 与色彩；与 `croppedToInstancesExtent` 的裁切配合。
- **替代**：`NSBitmapImageRep` 转 PNG——引入 AppKit，放弃。

### D5：`PetAssetStore` 与 `LocalCutoutGenerator` 的写盘职责边界

- **选择**：`LocalCutoutGenerator` 产出 masked `CGImage` 与元数据，由 `PetAssetStore.writeSprite(_:id:)` 负责落 `pets/<uuid>/sprite.png` + `meta.json` 并返回 URL；generator 通过注入的 store（或写盘闭包）完成持久化，不自行拼路径。
- **理由**：单一持久化入口便于复用、测试可注入临时根目录（沿用 M0 D5/可注入路径）；切宠物即切 `activePetID`，store 不耦合配置。
- **替代**：generator 自己写盘——路径逻辑散落、难注入测试目录，放弃。
- **目录权限**：复用 M0 的「确保 VibePet 支持目录存在」逻辑（参见 M0 TD-3 统一工具方法的方向），`pets/` 在用户私有支持目录下。

### D6：`GenerationService` 注册表 + 配置选择，未知 id 兜底

- **选择**：`GenerationService` 持有 `[identifier: PetGenerator]` 注册表，MVP 注册 `LocalCutoutGenerator`；`generate(from:)` 读 `config.activeGeneratorID` 选实现；未知/缺失 id → 回退到默认 `local-cutout` 并记录，或抛 typed `GenError`（二选一，落码时定为「回退到 local-cutout」以保证首启可用）。
- **理由**：新增生成器零侵入（§2.3）；首启或配置漂移不应阻塞生成（§7 可靠性）。
- **替代**：硬编码直接 new `LocalCutoutGenerator`——违背可插拔目标，放弃。

### D7：离线基准作为独立可执行/测试，不进 App

- **选择**：基准实现为 `Tools/CutoutBenchmark/`（独立 executable）或 `Tests/Benchmarks/CutoutBenchmark.swift`；读 `Tests/Fixtures/photos/` 下带标签清单（如 `manifest.json` 标 `clearSubject`/`edgeHard`/`lowContrast`/`multiSubject`），跑 generator，输出每张耗时 + P50/P95 + 按标签分母/可用率。
- **理由**：KPI 是离线评测，不应耦合 UI/CI 主流程；产出供人工边缘打分（§8.2）。
- **替代**：把基准塞进单测断言主观质量——主观可用率无法自动断言，放弃；脚本只产结构化结果，人工判定 ≥90%/≥80%。
- **照片版权**：fixture 照片须自有/可商用授权，避免引入第三方版权图（§11 精神）。

## Risks / Trade-offs

- **[`VNGenerateForegroundInstanceMaskRequest` 仅 macOS 14+ 且不同硬件耗时差异大]** → 平台已锁 macOS 14（Package.swift）；耗时差异由 §8.2 基准在固定机器上量化，KPI 以 P50/P95 表达而非单张。
- **[`largestInstance` 在 multiSubject 上可能选错主体]** → MVP 明确只取面积最大者、记录为已知限制；`multiSubject` 标签在基准里单列分母，多主体点选排入后续版本。**已实测确认**（`multiSubject` 可用率 33%，见「基准实测结果与已知限制」），作为已接受的 MVP 限制。
- **[masked 图 alpha 在 PNG 编码/裁切环节被压平]** → 用 ImageIO `CGImageDestination` 全程保 alpha，单测断言输出 PNG 含 alpha 通道且非空。
- **[Vision API 在无主体/极低对比度图上不抛错而返回空蒙版]** → 显式判 `results` 为空/无有效实例 → `GenError.noSubject`；`lowContrast`/`edgeHard` 标签在基准里覆盖这些边界。
- **[Application Support 写入污染真实用户目录/测试]** → `PetAssetStore` 接受可注入根路径，测试用临时目录（沿用 M0 模式）。
- **[Swift 6 严格并发：`generate` 是 `async` 且回调 `progress`]** → generator 为值类型 `Sendable`，`progress: @escaping (Double) -> Void` 由调用方在合适 actor 上消费；store 的可变文件 I/O 用串行隔离。
- **[基准照片集尚未就位]** → fixture 与标签清单作为 M1-5 交付的一部分；M1-2 的单测先用 1~2 张单主体/无主体小图验证功能，不依赖完整 20 张集。

## Migration Plan

属新增 core 能力，无存量迁移。落地顺序遵循任务级依赖：M1-1（协议+模型）→ {M1-2（LocalCutoutGenerator）、M1-3（PetAssetStore）}（均依赖 M1-1）→ M1-4（GenerationService，依赖 M1-1/M1-2 + M0-6 ConfigStore）→ M1-5（基准，依赖 M1-2/M1-3）。M1 仅依赖 M0-1/M0-6，可与 M2/M3 并行。回滚＝删除 `VibePetCore/Generation/` 与 `PetAssetStore.swift` 及相关测试，无外部系统影响。

## 基准实测结果与已知限制（M1-5 / 6.2 验收记录）

人工核验后对 18 张带标签照片集跑 `CutoutBenchmark` 的结果：

| KPI | 阈值 | 实测 | 结论 |
| --- | --- | --- | --- |
| P50 延迟 | ≤ 3s | 0.08s | ✅ |
| P95 延迟 | ≤ 8s | 0.35s | ✅ |
| `clearSubject` 可用率 | ≥ 90% | 88%（7/8） | ❌ |
| 全集可用率 | ≥ 80% | 78%（14/18） | ❌ |

按标签可用率：`clearSubject` 88%(7/8)、`edgeHard` 100%(1/1)、`lowContrast` 83%(5/6)、`multiSubject` 33%(1/3)。

**已知限制（接受，排入后续版本）：**

- **多主体选错主体**：`multiSubject` 33% 是全集/`clearSubject` 两项可用率未达标的主因，与 D3 风险表一致——MVP 的 `largestInstance` 仅取面积最大主体，多主体场景预期会选错。MVP 明确接受此限制；多主体点选/合成排入后续版本。评估 MVP 抠图能力时，`multiSubject` 单列、不计入必达项。
- **样本量偏小**：当前 18 张（规格目标 20 张，`edgeHard` 仅 1 张），分母小导致单张挂掉即拉低 5~12 个百分点，统计噪声大；后续补满样本可让数字更稳。`clearSubject` 88% 仅差一张即达 90%。
- 延迟 KPI 大幅达标（本地 Vision，P95 较 8s 阈值有约 20× 余量），非瓶颈。

## Open Questions

- `GenerationService.generate(from:)` 是否需要把 `progress` 透传给调用方？倾向透传（`generate(from:progress:)`），M2 进度条直接消费；落码时与 M2-5 的 view model 接口对齐。
- `meta.json` 的字段集合以能重建 `PetAsset` 为准（id/kind/boundingInset/metadata/layers 引用）；若 M2 动画需要更多字段，按「缺字段走默认」向后兼容增补。
- ~~基准照片集放仓库还是 LFS？~~ **已定**：小尺寸自有/可商用授权图直接入仓 `Tests/Fixtures/photos/` + `manifest.json`，不使用 Git LFS（避免 CI/clone 额外依赖）。需控制单张尺寸（建议长边 ≤ 1600px、单张 ≤ ~500KB），照片由维护者准备并打标签。
