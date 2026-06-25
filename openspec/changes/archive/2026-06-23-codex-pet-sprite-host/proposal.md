## Why

VibePet 当前的宠物是「单张静帧 + 程序化捏脸」：`PetView` 只持有一张 `CGImage`，靠 SwiftUI 的 `scaleEffect`/旋转/眨眼图层假装活着，根本没用上 spritesheet 的多帧。它无法表达 agent 的真实活动状态，与「桌面宠物」的产品初衷脱节——拿到一个 Codex 宠物文件却只能静态展示，没有意义。

本 change 把宠物资源模型从「照片抠图单 PNG + 程序化动画」**整体替换**为 **标准 Codex 宠物格式（spritesheet）**，并新增**真·逐帧精灵动画**渲染器，使宠物用 Codex 官方约定的 9 行精灵、按每帧可变时长循环播放，由会话状态驱动「行」，像 Codex 本体一样动起来。

## What Changes

- **新增精灵动画渲染**：加载 spritesheet（8 列 × 9 行、192×208 单元格、1536×1872），按当前宠物状态选「行」，逐帧循环播放，**采用 Codex 官方 per-frame 时长表**（非匀速），尾部透明帧跳过。
- **内建 Codex 动画约定表**：9 行的绝对行号、每行有效帧数、每帧毫秒时长来自官方 `hatch-pet/animation-rows.md`，硬编码进 Core（`pet.json` 不携带这些时它就是唯一来源）。
- **状态→行映射忠实对齐 Codex 语义**：等审批/提问→`waiting`(行6)、干活→`running`(行7)、打招呼/干净完成→`waving`(行3)、失败→`failed`(行5)、空闲→`idle`(行0)；位移类 `running-right/left`(1/2)、`jumping`(4)、`review`(8) 本版无信号驱动，不用。
- **宠物来源改为多根聚合**：共享 `~/.codex/pets/<slug>/`（只读、原地引用、Codex 新装即出现）+ VibePet 导入目录，按 slug 去重（导入优先）。**本版不含自带宠物**。
- **拖拽导入支持 zip 为主 + 文件夹兼收**：拖入标准 Codex 宠物 zip（pet.json + spritesheet 在包根）→ 解压校验落地；拖入文件夹 → 校验拷入；两者均**容忍单层包裹目录**（如 Finder 压缩出的 `boba/pet.json`）。
- **空状态引导**：无任何可用宠物时显示平台中立的可读引导（任意方式装进 `~/.codex/pets/` 或直接拖入），而非空白/崩溃。
- **命中穿透改吃「当前帧」alpha**：透明区域鼠标穿透按当前播放帧的 alpha 建掩码，仅本体响应拖动/点击。
- **Reduce Motion 降级**：降为该状态行第 0 帧静帧。
- **BREAKING 删除抠图管线**：移除 `Generation/`（PetGenerator/LocalCutoutGenerator/GenerationService/PetImportStateMachine）、旧 `PetImportPanel`、`PetView`/`PetAnimations` 单图渲染、`Tools/CutoutBenchmark`、`Tests/Fixtures/photos/`，及对应旧 spec。代码已存档于 `docs/archive/2026-06-22-抠图管线代码存档.md`。
- **老用户直接丢弃**：升级后若存在旧 `~/Library/Application Support/VibePet/pets/<UUID>/`（meta.json/sprite.png），聚合读取器按「非 Codex 格式」忽略——不崩、不迁移、不提示。

## Capabilities

### New Capabilities
- `sprite-animation`: spritesheet 切片、9 行 Codex 约定的绝对行号与 per-frame 时长表、状态→行映射、非匀速逐帧步进、尾部透明帧跳过、Reduce Motion 降级、按当前帧 alpha 的命中穿透。
- `codex-pet-source`: 多根聚合读取（`~/.codex/pets` 原地引用 + 导入目录）、Codex `pet.json` 解析与校验、slug 去重、共享目录缺失返回空、非法/旧 UUID 宠物跳过不崩、空状态。
- `codex-pet-import`: 拖拽导入 zip（为主）+ 文件夹（兼收），解压、单层包裹目录容忍、校验后按 slug 落地到导入目录。

### Modified Capabilities
<!-- 旧抠图 specs（pet-generation / cutout-quality-benchmark / pet-import-panel / pet-generator-protocol / pet-asset-store / pet-view-animation）是移除或被上述新 capability 取代，非 requirement 微调，故不在此列为 delta。移除在 tasks 中处理。 -->

## Impact

- **Core（VibePetCore，保持 UI 无关、可测）**：新增 spritesheet 切片/网格/状态→行/当前帧 alpha 掩码逻辑与内建 durations 表；`PetAssetStore` 改为多根聚合读取器 + Codex `pet.json` 解析；`PetAsset` 由「UUID 单图」改为「Codex 文件夹引用（slug）」；`PetVisualState` 派生（含 `review`→`waiting` 改名）。
- **App（VibePetApp）**：`PetView` 改为 `SpriteSheetAnimator` 逐帧渲染（`TimelineView` 非匀速步进）；`PetController`/`PetStateMachine` 对接新状态；Onboarding ②步「挑宠物」+ 空状态；设置页/菜单栏「切换宠物」+「导入宠物…」；命中掩码改当前帧。
- **删除**：`Generation/`、`Tools/CutoutBenchmark`、旧导入面板、抠图测试夹具与旧 spec；`swift package describe` 目标列表随之变化。
- **依赖/系统**：spritesheet `.webp` 解码走系统 `ImageIO`/`CGImageSource`（macOS 14 原生支持，无第三方库）；只读引用真实 `~/.codex/pets/`。保持**纯本地、无网络**（不做画廊在线安装/CLI 集成）。
- **护栏**：改写 `CLAUDE.md` 中抠图/CutoutBenchmark 相关条款为「Codex 宠物宿主、本地优先、无网络生成、改 SpriteSheetAnimator/PetAssetStore 时跑 swift test」。
- **测试**：聚合去重/缺失/非法跳过、`pet.json` 解析、状态→行映射、切片/透明帧跳过/当前帧 alpha 命中、zip 与文件夹导入（含单层目录容忍）、删除回归（`swift build`/`swift test` 无悬挂引用）。**仅单测、不做真实冒烟**（写入可能命中真实 `~/.codex`）。
