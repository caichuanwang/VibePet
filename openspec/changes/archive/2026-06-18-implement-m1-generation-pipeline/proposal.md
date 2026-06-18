## Why

M0 已就位工程骨架与 Bridge 数据模型，但 VibePet 还无法把一张照片变成宠物。里程碑 M1 是产品的第一个用户价值：**脱离 UI、完全离线**地把照片抠成带透明通道的精灵 PNG 并持久化，对应 PRD US-1 与抠图相关 KPI。它是 M2（桌面宠物窗）导入面板的前置——没有可调用的生成与素材存储，M2-5 无从落地。

本次变更覆盖技术方案 §2 / §6（pets 目录与 PetAssetStore）/ §8.2，以及任务拆解 M1-1 ~ M1-5 的全部内容。

## What Changes

- 在 `VibePetCore/Generation` 定义可插拔生成抽象：`PetGenerator` 协议（`identifier` / `generate(from:progress:)`）、`PetAsset` / `PetKind`（`sprite2D`/`stylized2D`/`model3D`）/ `PetLayer` / `GenError`（含 `.noSubject`）模型（§2），`PetAsset` 可 Codable 往返。
- 实现 MVP 生成器 `LocalCutoutGenerator`：用 `VNGenerateForegroundInstanceMaskRequest` 本地抠主体，多主体取面积最大者（`largestInstance`），`croppedToInstancesExtent` 裁到主体范围，无显著主体抛 `GenError.noSubject`，输出带透明通道 PNG，并驱动 `progress` 回调（§2.1）。
- 实现 `PetAssetStore`：把精灵写入 `pets/<uuid>/sprite.png` + `meta.json`，支持按 id 读取/列举/删除，切换不影响其它宠物素材（§6）。
- 实现 `GenerationService` 选择器：依据 `config.activeGeneratorID` 从注册表取 `PetGenerator`，对外只暴露 `generate(from:)`；MVP 注册 `LocalCutoutGenerator`，未知 id 有明确兜底/报错；新增生成器只需注册、不改调用方（§2.3）。
- 新增离线生成质量基准：对 20 张带 `clearSubject`/`edgeHard`/`lowContrast`/`multiSubject` 标签的固定测试照片集跑 `LocalCutoutGenerator`，汇总 P50/P95 耗时并输出供人工边缘打分的结果，可判定 P50 ≤ 3s、P95 ≤ 8s、清晰主体子集可用率 ≥ 90% / 全量 ≥ 80%（§8.2）。
- 全部上述模型、生成器、存储与服务附带单元测试（编解码往返、抠图产出、读写往返、选择器路由）。

## Capabilities

### New Capabilities
- `pet-generation`: 照片 → 宠物素材的可插拔生成管线——`PetGenerator` 协议、`PetAsset`/`PetKind`/`GenError` 模型、本地 Vision 抠图实现 `LocalCutoutGenerator`，以及按配置选择生成器的 `GenerationService`。
- `pet-asset-store`: 宠物精灵与元数据在 `pets/<uuid>/` 下的持久化、读取、列举与删除。
- `cutout-quality-benchmark`: 对固定标签照片集离线评测 `LocalCutoutGenerator` 时延与可用率的基准工具及其 KPI 判据。

### Modified Capabilities
<!-- 无：`GenerationService` 只读取 M0 既有 `app-configuration` 的 `activeGeneratorID` 字段，不改变其 spec 级行为；故不产生 app-configuration 的 delta。 -->

## Impact

- **新增源码**：`VibePetCore/Generation/`（`PetGenerator.swift`、`LocalCutoutGenerator.swift`、`GenerationService.swift`）、`VibePetCore/Persistence/PetAssetStore.swift`。
- **新增测试与 fixtures**：`Tests/VibePetCoreTests/`（`PetAssetCodecTests`、`LocalCutoutGeneratorTests`、`PetAssetStoreTests`、`GenerationServiceTests`）、基准工具（`Tools/CutoutBenchmark/` 或 `Tests/Benchmarks/CutoutBenchmark.swift`）、测试照片集 `Tests/Fixtures/photos/`。
- **新增运行时副作用**：在 `~/Library/Application Support/VibePet/pets/<uuid>/` 下写入 `sprite.png` 与 `meta.json`（仅当前用户）。
- **依赖**：纯 Apple 原生框架（Vision / CoreImage / CoreGraphics / ImageIO / Foundation）；无第三方依赖，全程不联网。
- **复用 M0**：`GenerationService` 读取 `app-configuration` 的 `activeGeneratorID`；`PetAsset` 与既有 `Codable`/`Sendable` 约定一致。
- **下游解锁**：M2-5 导入→生成面板与 M2-2 宠物视图直接消费 `GenerationService.generate(from:)`、`PetAssetStore` 与 `PetAsset.layers`。
