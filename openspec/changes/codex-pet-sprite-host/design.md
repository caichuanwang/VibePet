## Context

VibePet 现状是「伪动画」：`VibePetApp/Pet/PetView.swift` 只持有一张 `@State var sprite: CGImage?`，靠 `PetAnimations.swift` 的 `scaleEffect`/旋转/眨眼图层做程序化呼吸摇摆，从不读 spritesheet 多帧。要让宠物「像 Codex 本体一样动起来」，必须换成真·逐帧精灵动画。

经实测真实宠物 `~/.codex/pets/trump/`：`pet.json` 只有 4 个字段（`id`/`displayName`/`description`/`spritesheetPath`），**不含**网格/帧数/时长/状态行；spritesheet `1536×1872` 完美对上 8×9×192×208。也就是说——**「怎么动」的知识不在宠物文件里，而在渲染器侧的约定**。官方契约 `hatch-pet/references/codex-pet-contract.md` 印证：「The webview animation uses CSS background positions from the fixed row and column counts.」

权威动画约定（金标准，来自本地官方 `hatch-pet/references/animation-rows.md`）：

| Row | State | 有效列 | per-frame durations (ms) |
|---:|---|---:|---|
| 0 | idle | 0–5 (6) | 280,110,110,140,140,320 |
| 1 | running-right | 0–7 (8) | 120×7,220 |
| 2 | running-left | 0–7 (8) | 120×7,220 |
| 3 | waving | 0–3 (4) | 140,140,140,280 |
| 4 | jumping | 0–4 (5) | 140×4,280 |
| 5 | failed | 0–7 (8) | 140×7,240 |
| 6 | waiting | 0–5 (6) | 150×5,260 |
| 7 | running | 0–5 (6) | 120×5,220 |
| 8 | review | 0–5 (6) | 150×5,280 |

约束：`VibePetCore` 不引入 AppKit/SwiftUI（切片/网格/状态→行/当前帧 alpha 在 Core 保持可测，绘制在 App）；纯本地、无网络；写入可能命中真实 `~/.codex`，仅单测、不做真实冒烟。

## Goals / Non-Goals

**Goals:**
- 用 spritesheet 9 行 + Codex 官方 **per-frame 可变时长**做真逐帧循环动画，节奏与 Codex 一致（看起来在「呼吸/活着」）。
- 状态→行映射**忠实对齐 Codex 语义**，行号用绝对值。
- 多根聚合宠物来源（`~/.codex/pets` 原地引用 + 导入目录），zip 为主 + 文件夹兼收的拖拽导入。
- 命中穿透吃当前帧 alpha；Reduce Motion 降级静帧；空状态引导。

**Non-Goals:**
- 不用位移/跳跃/审查行（running-right/left=1/2、jumping=4、review=8）——本版 `SessionState` 无对应信号。
- 不做 App 内画廊浏览、网络在线安装、petdex CLI 集成。
- 不做自带宠物、不做老用户迁移。
- 不改会话模型/hook（子项目1）、终端跳回（子项目3）。

## Decisions

### D1. per-frame 异步步进，拒绝统一帧率
**选 Core Animation/统一帧率之外的「按 durations 表逐帧步进」。** 关键洞见：idle 行 `280,110,110,140,140,320`（头帧停 280ms、末帧停 320ms、中间快闪）——正是这种「停—闪—停」的非匀速节奏让它看起来活着；总和恰好 1100ms（设计文档旧 `loopMs=1100` 抓到了周期却丢了节奏）。
- 实现：App 侧一个 `@State frameIndex` + 一个驱动循环（`Task` 内 `try await Task.sleep(durations[i])` 递归推进，或等价 timeline）。View 观察 `frameIndex` 取 `frames[row][col]` 绘制。
- 备选（拒绝）：`TimelineView(.animation)` / `.periodic` 固定步长 → 匀速机械感，丢节奏。`.explicit(dates)` 需预算 dates，循环时还要不断重排，复杂度不划算。

### D2. 行号用绝对值表，不用「声明顺序兜底」
内建一张 `[PetVisualState: (row: Int, durations: [Int])]` 表（或行号 + 行→durations 两表）。`running` 是第 **7** 行不是第 1 行，`waiting` 是第 6 行。设计文档旧 §5「canonical 顺序 idle/running/review/... 兜底」会错位，废弃。

### D3. `PetVisualState.review` 改名 `.waiting`
忠实对齐后「等审批/提问」实际播 Codex 的 `waiting`(6)，而 Codex `review`(8) 无信号驱动、不用。保留 `review` 名会留下「review 态却播 waiting 行」的隐藏错位 → 改名 `.waiting`。最终用到 5 行：`idle=0 / waving=3 / failed=5 / waiting=6 / running=7`。

### D4. pet.json：内建表兜底 + 声明优先
真实最小契约 pet.json 不带 durations；但 petdex 画廊宠物**可能**带扩展字段（slug/tags/states/frame durations，二手信息、未一手确认）。解析器策略：**内建 Codex 官方表为兜底；若 pet.json 显式声明某行 durations 则尊重声明**。这样兼容两种形态，且不依赖未确认的扩展存在。

### D5. webp 走系统 ImageIO
spritesheet `.webp` 用 `CGImageSource`/`ImageIO` 解码（已用 `sips` 验证 macOS 14 原生可解，生成 3.1M PNG），不引第三方库。切片 = 对解码后整图按 (row,col)×(192,208) 裁 `CGImage`。

### D6. 当前帧 alpha 命中掩码
复用 `SpriteHitMask` 思路，但掩码源从「单图」改为「**当前播放帧**」，随 `frameIndex` 切换重建。为控开销，掩码可降采样到低分辨率 alpha 网格（命中判定不需像素级精度）。

### D7. 导入：zip 为主 + 文件夹兼收 + 单层目录容忍
拖入 `.zip` → 解压到临时目录 → 向下定位含 `pet.json` 的层（容忍 `boba/` 单层包裹）→ 校验网格 → 按 slug 拷入导入目录；拖入文件夹 → 同样「定位 pet.json 层 → 校验 → 拷入」。复用存档导入状态机的「拖入 → 校验 → 落地」流程划分。

### D8. 抠图整体删除（先存档已完成）
删 `Generation/`、`Tools/CutoutBenchmark`、旧 `PetImportPanel`、`PetView`/`PetAnimations` 单图渲染、`Tests/Fixtures/photos/` 及旧 spec；`SpriteHitMask` 保留（复用到逐帧 alpha），`ImageLoading` 视复用精简。

## Risks / Trade-offs

- **每帧重建命中掩码开销** → D6 降采样 alpha；必要时合并相邻帧 alpha 或仅对代表帧建掩码（spike #4）。
- **petdex 扩展 pet.json 形态未一手确认** → D4 以内建表兜底，不依赖扩展存在；用 spike inspect 一个真实 petdex 宠物（如 boba）落实，再决定是否真读声明。
- **webp 多样本解码差异** → 已验证 trump 可解；导入校验阶段对解码失败的 spritesheet 走「跳过 + 可读原因」，不崩。
- **`pet.json` 缺字段/异形** → 解析容错：缺关键字段或网格不符即跳过/拒绝并记录原因，单宠物失败不影响聚合。
- **行序约定随 Codex 演进变化** → 内建表集中一处，便于未来跟随官方 `animation-rows.md` 更新；不散落到 UI。

## Migration Plan

1. 在 Core 落地 `PetAsset`(slug 形态) + 聚合读取器 + Codex `pet.json` 解析/校验 + 内建 9 行 durations 表 + 状态→绝对行映射（`review`→`waiting`）+ 当前帧 alpha 掩码。
2. App 落地 `SpriteSheetAnimator`（per-frame 步进）替换 `PetView`/`PetAnimations` 单图渲染；对接 `PetController`/`PetStateMachine`。
3. UI：Onboarding ②「挑宠物」+ 空状态；设置页/菜单栏「切换宠物」+「导入宠物…（zip/文件夹）」。
4. 删除抠图管线与旧 spec；改写 `CLAUDE.md` 护栏。
5. 回归：`swift build` / `swift test` 通过、无悬挂引用；`swift package describe` 目标列表一致（CutoutBenchmark 已移除）。
- **回滚**：本 change 为整体替换且无线上用户，回滚 = 还原 git；存档文档保留抠图原代码可恢复。

## Open Questions

1. **spike**：inspect 一个真实 petdex 画廊宠物（如 `boba`）的 `pet.json`，确认是否真带 states/frame durations 扩展字段；据此定 D4 是否真正读取声明。
2. **spike**：多个画廊样本行序是否都遵循官方 9 行约定（确认内建表对非官方宠物的适配面）。
3. **spike**：每帧重建 `SpriteHitMask` 的真实开销，决定降采样粒度 / 是否合并 alpha。
4. 拖动中（用户拖宠物）是否切到某种「被拎起」表现——本版无对应行，默认维持当前状态行，留待后续。
