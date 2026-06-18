## 1. M1-1 · PetGenerator 协议与 PetAsset 模型

- [x] 1.1 在 `VibePetCore/Generation/PetGenerator.swift` 定义 `PetGenerator` 协议（`Sendable`）：`var identifier: String`、`func generate(from image: CGImage, progress: @escaping (Double) -> Void) async throws -> PetAsset`
- [x] 1.2 定义 `PetAsset`（`id: UUID`、`kind: PetKind`、`primaryImageURL: URL`、`layers: [PetLayer]`、`boundingInset`、`metadata: [String: String]`）、`PetKind`（`sprite2D`/`stylized2D`/`model3D`）、`PetLayer`，全部 `Codable`+`Sendable`；`boundingInset` 用 UI 无关类型（自定义 `PetEdgeInsets`，非 SwiftUI `EdgeInsets`，见 design D2）
- [x] 1.3 定义 `GenError`（含 `.noSubject`，及其它生成失败 case），`Error`+`Sendable`
- [x] 1.4 在 `Tests/VibePetCoreTests/PetAssetCodecTests.swift` 写编解码往返单测：`PetAsset` 各字段往返保真、`PetKind` 各 case 原始值稳定（验收：M1-1）

## 2. M1-2 · LocalCutoutGenerator（Vision 抠图）

- [x] 2.1 在 `VibePetCore/Generation/LocalCutoutGenerator.swift` 实现 `PetGenerator`，`identifier == "local-cutout"`；用 `VNGenerateForegroundInstanceMaskRequest` + `VNImageRequestHandler(cgImage:)` 抠前景；`results` 为空/无有效实例 → 抛 `GenError.noSubject`
- [x] 2.2 多主体时按蒙版面积取最大实例（`largestInstance`）；`generateMaskedImage(ofInstances:from:croppedToInstancesExtent:true)` 得裁切后带 alpha 的 `CGImage`
- [x] 2.3 用 ImageIO `CGImageDestination`（UTType `.png`）把 masked 图写盘，保留 alpha；经注入的 `PetAssetStore`/写盘闭包落 `pets/<uuid>/sprite.png` 并返回 URL（写盘职责见 design D5）；失败路径不落半成品
- [x] 2.4 在生成各阶段调用 `progress` 回调（值域 0.0…1.0，至少一次）；返回 `PetAsset(kind: .sprite2D, layers: [], ...)`
- [x] 2.5 在 `Tests/VibePetCoreTests/LocalCutoutGeneratorTests.swift` 写单测（fixtures：单主体小图、无主体小图）：单主体产出非空且含 alpha 的 PNG、无主体抛 `GenError.noSubject`（不落文件）、`progress` 被调用（验收：M1-2）

## 3. M1-3 · PetAssetStore 资源持久化

- [x] 3.1 在 `VibePetCore/Persistence/PetAssetStore.swift` 实现写入：把精灵写 `pets/<uuid>/sprite.png`（保 alpha）+ `meta.json`（足以重建 `PetAsset`）；支持可注入根路径以便测试；复用 M0「确保支持目录存在」逻辑（用户私有目录）
- [x] 3.2 实现按 id 读取（载入 `PetAsset` + 可读 sprite）、列举所有 pet id、按 id 删除；读缺失 id 返回 nil/typed error 不崩
- [x] 3.3 在 `Tests/VibePetCoreTests/PetAssetStoreTests.swift` 写单测：写后读往返一致且 alpha 保真、列举含两只宠物、删除其一不影响另一只、读缺失 id 不崩（验收：M1-3）

## 4. M1-4 · GenerationService 选择器

- [x] 4.1 在 `VibePetCore/Generation/GenerationService.swift` 实现注册表 `[identifier: PetGenerator]`，MVP 注册 `LocalCutoutGenerator`；据 `config.activeGeneratorID`（来自 `ConfigStore`/`AppConfig`）选实现，对外暴露 `generate(from:progress:)`
- [x] 4.2 未知/缺失 `activeGeneratorID` → 回退到默认 `local-cutout`（design D6）；保证未注册 id 不崩、行为确定
- [x] 4.3 在 `Tests/VibePetCoreTests/GenerationServiceTests.swift` 写单测：`activeGeneratorID == "local-cutout"` 路由到 `LocalCutoutGenerator`、未知 id 走兜底不崩、新注册的 mock generator 经配置选中且调用方不变（验收：M1-4）

## 5. M1-5 · 离线生成质量基准脚本

- [x] 5.1 准备测试照片集 `Tests/Fixtures/photos/`（以 `manifest.json` 声明的固定照片集为准，当前 18 张，**自有/可商用授权**，由维护者提供）+ `manifest.json`，每张标 `clearSubject`/`edgeHard`/`lowContrast`/`multiSubject`（可多标签）；照片**直接入仓、不用 LFS**，控制尺寸（建议长边 ≤ 1600px、单张 ≤ ~500KB）
- [x] 5.2 在 `Tools/CutoutBenchmark/`（独立 executable）或 `Tests/Benchmarks/CutoutBenchmark.swift` 实现：读 manifest、对每张跑 `LocalCutoutGenerator`、记录每张耗时
- [x] 5.3 汇总输出 P50/P95 总耗时、按标签分母与可用率（供人工边缘打分），结构化结果可判定 P50 ≤ 3s、P95 ≤ 8s、`clearSubject` 子集可用率 ≥ 90% / 全量 ≥ 80%（验收：M1-5、§8.2）

## 6. 里程碑收尾验收

- [x] 6.1 `swift build && swift test` 全绿，M1 新增单测（PetAsset 编解码、LocalCutout 抠图、PetAssetStore 往返、GenerationService 路由）通过
- [x] 6.2 跑基准脚本产出 P50/P95 与按标签可用率，记录是否达标（达标即满足抠图 KPI；未达标列出短板供后续优化）
- [x] 6.3 确认 M1 全程不 import AppKit/SwiftUI、不联网，`GenerationService.generate(from:)` 可被 M2 直接消费（对外接口与 M2-5 view model 对齐）
