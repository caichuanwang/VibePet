## ADDED Requirements

### Requirement: Spritesheet 网格切片

渲染器 SHALL 将 Codex spritesheet 按固定 8 列 × 9 行、每单元 192×208px（整图 1536×1872）切片为可按「行号 0–8 / 列号 0–7」寻址的 72 帧。切片逻辑 MUST 保持在 `VibePetCore`（UI 无关、可测），实际绘制在 App。

#### Scenario: 标准图集切片
- **WHEN** 加载一张 1536×1872 的合法 spritesheet
- **THEN** 切出 72 帧，每帧 192×208，可按 (row,col) 取任意单元

#### Scenario: webp 解码
- **WHEN** spritesheet 为 `.webp`
- **THEN** 通过系统 `ImageIO`/`CGImageSource` 解码成功，无需第三方库

### Requirement: 状态到绝对行映射（忠实对齐 Codex）

渲染器 SHALL 用固定**绝对行号**把 `PetVisualState` 映射到 Codex 行，不得用「第 N 个状态 = 第 N 行」的顺序兜底：`idle→0`、`waving→3`、`failed→5`、`waiting→6`、`running→7`。位移/跳跃/审查类行（`running-right=1`、`running-left=2`、`jumping=4`、`review=8`）本版无信号驱动，不使用。

#### Scenario: 等审批播 waiting 行
- **WHEN** 宠物状态为 `waiting`（存在 requiresAttention 会话：waitingForApproval / waitingForAnswer）
- **THEN** 渲染器播放第 **6** 行（waiting），而非第 8 行（review）

#### Scenario: 干活播 running 行
- **WHEN** 宠物状态为 `running`（存在 running 会话且无 requiresAttention）
- **THEN** 渲染器播放第 **7** 行

#### Scenario: 空闲播 idle 行
- **WHEN** 无活跃会话
- **THEN** 渲染器播放第 **0** 行

### Requirement: per-frame 可变时长逐帧播放

渲染器 SHALL 用**内建 Codex per-frame 时长表**（非匀速）循环播放当前行，不得用单一统一帧率。缺省内建表来自官方 `hatch-pet/references/animation-rows.md`；当某宠物的 `pet.json` 显式声明了该行 durations 时 SHALL 尊重声明，否则用内建表兜底。

#### Scenario: idle 行非匀速节奏
- **WHEN** 播放 idle 行
- **THEN** 6 帧依次按 `280,110,110,140,140,320` ms 推进并无限循环

#### Scenario: 各行内建时长
- **WHEN** 播放任一受支持行
- **THEN** 采用内建表：waving `140,140,140,280`(4帧)、failed `140×7,240`(8帧)、waiting `150×5,260`(6帧)、running `120×5,220`(6帧)

### Requirement: 未用列与尾部透明帧跳过

渲染器 SHALL 只循环该行的「有效列」，跳过尾部全透明单元格。

#### Scenario: waving 只播 4 帧
- **WHEN** 播放 waving 行（有效列 0–3）
- **THEN** 只循环前 4 帧，不播放第 4–7 的透明单元格

### Requirement: Reduce Motion 降级静帧

当系统开启 Reduce Motion 时，渲染器 SHALL 显示当前状态行第 0 帧静帧并停止逐帧循环。

#### Scenario: 降级为静帧
- **WHEN** Reduce Motion 开启且状态为 `running`
- **THEN** 显示第 7 行第 0 帧，不播放动画

### Requirement: 当前帧 alpha 命中穿透

命中掩码 SHALL 取**当前播放帧**的 alpha：全透明像素穿透到下层窗口，仅非透明本体响应拖动/点击；掩码 MUST 随帧切换更新。

#### Scenario: 透明区域穿透
- **WHEN** 鼠标点击落在当前帧的全透明像素上
- **THEN** 事件穿透到下层窗口，宠物不响应

#### Scenario: 本体响应
- **WHEN** 鼠标点击落在当前帧的非透明像素上
- **THEN** 宠物响应拖动/点击
