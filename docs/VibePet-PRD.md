# VibePet 产品需求文档

> 平台：macOS 14+（Sonoma 及以上）· Swift 6.x · SwiftUI + AppKit · 纯原生（非 Electron）
> 当前产品阶段：**0.2 转型期**（0.1 MVP 已实现并落到代码，0.2 三个子项目设计完成、待实现）
> 维护原则：发新版本时只需**适当修订本文**（更新产品定位、架构演进、代码锚点、路线图），具体功能仍以对应 spec 为准。

---

## 0. 文档体系与阅读指南

VibePet 的文档分三层，职责单向依赖、互不重复：

| 层 | 位置 | 承载内容 | 稳定性 |
|---|---|---|---|
| **主 PRD（本文）** | `docs/VibePet-PRD.md` | 产品定位、组织架构、代码参考、横切技术方案、路线图 | 高（跨版本复用） |
| **归档 archive** | `docs/archive/` | 已完成/已退役版本的 PRD、技术方案、任务拆解、代码存档 | 冻结（只读历史） |
| **OpenSpec 规格** | `openspec/specs/` | 每个能力的形式化 spec（粒度到能力单元） | 跟随实现演进 |

**常见查阅路径**：

- 理解项目是什么、为何这样组织 → **本文**。
- 某功能当前怎么设计、验收标准 → `docs/superpowers/specs/` 对应子项目文档。
- 某能力的历史实现（如已退役的照片抠图算法）→ `docs/archive/`。
- 改某个能力前看形式化规格 → `openspec/specs/<capability>/`。

**当前版本 specs 索引（0.2）**：

| 子项目 | 文档 | 一句话 |
|---|---|---|
| 1 · 地基块 | `superpowers/specs/2026-06-22-vibepet-0.2-foundation-session-model-design.md` | 持久多会话 `SessionState` reducer + 全 hook 生命周期覆盖 |
| 2 · 宠物宿主 | `superpowers/specs/2026-06-22-vibepet-0.2-pet-host-sprite-design.md` | 退役抠图，转 Codex spritesheet 宠物宿主 + 精灵动画 |
| 3 · 终端跳回 | `superpowers/specs/2026-06-22-vibepet-0.2-terminal-jumpback-design.md` | 气泡双击跳回来源终端 tab/session |

**已归档版本索引（0.1 MVP）**：`docs/archive/VibePet-MVP-PRD.md`、`VibePet-MVP-技术实现方案.md`、`VibePet-MVP-任务拆解.md`、`2026-06-22-抠图管线代码存档.md`。

---

## 1. 执行摘要（Executive Summary）

### 1.1 问题陈述

开发者重度使用 vibe coding 工具（Claude Code、Codex 等）时，AI Agent 频繁需要人工拍板——确认权限、批准命令执行、批准文件改动、回答多选题。这些"需要你决策"的时刻**只发生在终端里**：开发者一旦切走窗口就会错过，导致 Agent 空等、心流被打断、被迫频繁切回终端轮询"卡在哪了"。同时，开发者对"哪个会话正在跑、哪个在等我"缺乏一个跨终端、跨工具的统一视图。

### 1.2 解决方案

VibePet 是一个 macOS 原生**桌面宠物 + 深度 agent 集成**应用。一个会动的 2D 桌面宠物注册进各 vibe coding 工具的 hooks，把"提醒"与"决策"合并到一个可爱的桌面入口：

- **桌面气泡里直接决策**：Agent 需要审批/答复时，宠物在气泡里给出"允许一次/始终允许/拒绝"按钮或多选项，**点击即实时回传，无需切回终端**。
- **持续态而非一事件一气泡**：宠物动画反映会话的"持续状态"（正在跑工具 / 待审批 / 待答题 / 完成 / 失败 / 待机），并聚合多会话、多终端。
- **一键跳回来源终端**：任意气泡可双击跳回它所来自的终端窗口/tab。
- **宠物即生态**：宠物资源采用标准 **Codex 宠物格式（spritesheet）**，原地引用共享的 `~/.codex/pets/`，与整个 Codex 宠物生态打通。

### 1.3 产品定位与差异化

最深的交互式 agent 集成 + Codex 宠物生态宿主
- 改靠**横跨 Claude Code + Codex 的、能在桌面真实 allow/deny + 答多选题 + 跳回终端的深度集成**，配合 Codex 宠物市场的可爱外观。

### 1.4 成功标准（可度量 KPI）

| 指标 | 目标值 | 适用 |
|---|---|---|
| 决策回路闭环 | 工具触发决策 hook → 宠物气泡出现 → 点击按钮 → 对应决策反馈到工具。全链路 Demo 跑通。 | 长期核心 |
| 决策回路延迟 | 工具触发到气泡出现 ≤ 500ms（本地 Unix socket）。 | 长期核心 |
| Fail-open 可靠性 | App 未运行/连接失败/输入畸形/超时时，hook ≤ 2s 退出且不阻塞 Agent，成功率 100%；用户未响应按可配置倒计时（默认 20s）fail-open。 | 红线（不可退化） |
| 会话模型确定性 | 给定一串 `AgentEvent` 序列，reducer 产出确定的 `[sessionID: AgentSession]`（纯函数、单测覆盖）。 | 0.2 地基 |
| 多会话可见性 | 菜单栏可见活跃会话数与"需关注（待审批/待答题）"数。 | 0.2 |
| 精灵渲染 | 加载合法 Codex 宠物（`pet.json` + spritesheet 8×9 网格），按会话状态播放对应行、循环帧。 | 0.2 |
| 终端跳回 | 气泡双击 → 前台聚焦来源终端；5 个精确终端定位到具体 tab/session，其余 fail-open 兜底激活 App + cwd。 | 0.2 |

---

## 2. 产品背景与演进（Product Context）

### 2.1 用户画像（Personas）

**主画像 —— "心流开发者" Leo**：重度使用 Claude Code / Codex 的独立开发者/工程师，常同时开多个终端跑 Agent，讨厌频繁切窗口查看"Agent 卡在哪了"。希望一个不打扰、但关键时刻能一眼看到并一键处理的入口，且有点个性化、好玩。

**次画像 —— "桌宠玩家" Mia**：对 AI 桌宠、个性化装扮感兴趣。核心动机是"把一个可爱的宠物放到桌面陪我写代码"，对宠物外观的"可爱度"敏感；agent 集成是顺带使用。0.2 后她通过 Codex 宠物生态获取宠物，而非上传照片。

### 2.2 版本演进与定位转变

| 维度 | 0.1 MVP（已归档） | 0.2（当前方向） |
|---|---|---|
| 宠物来源 | 上传照片 → 本地 Vision 抠图 → 单张透明 PNG | 标准 Codex 宠物格式（spritesheet），原地引用 `~/.codex/pets/` + 拖拽导入 |
| 动画 | Core Animation 程序化呼吸/眨眼 | 9 行 spritesheet，按会话 phase 切行循环帧 |
| 状态模型 | 一事件一气泡（无状态 bridge） | 持久多会话 `SessionState` reducer（持续态 + 多会话聚合） |
| hook 覆盖 | `PreToolUse / Stop / Notification`（Claude）、`PermissionRequest / notify`（Codex） | 拓宽到全生命周期 hook（SessionStart/UserPromptSubmit/PostToolUse/Subagent*/SessionEnd/StopFailure/… ） |
| 终端跳回 | 非目标（排期 v1.1） | 子项目 3 实现，5 终端精确 + 兜底 |
| 差异化卖点 | "你的照片变桌宠" | "最深的 agent 集成 + Codex 宠物生态宿主" |

**退役说明**：照片抠图管线（`VNGenerateForegroundInstanceMaskRequest` + 程序化动画）在 0.2 子项目 2 落地时删除，核心算法与显示逻辑已逐字存档于 `docs/archive/2026-06-22-抠图管线代码存档.md`。**当前仓库代码中相关文件仍在**（见 §4 标注），将随子项目 2 实现一并移除。

### 2.3 跨版本非目标（Non-Goals）

以下在可预见范围内不做，除非有显式产品变更与授权：

- ❌ **网络生成 / 遥测 / 照片上传 / 账号云同步**：纯本地、无服务器、无登录（产品级护栏，见 `CLAUDE.md`）。
- ❌ **宠物 AI 对话 / LLM 人格**：宠物不接 LLM 聊天。
- ❌ **Windows / Linux**：仅 macOS。
- ❌ **App 内在线画廊安装宠物**：0.2 仅本地聚合（共享目录 + 拖拽导入），在线浏览/安装留后续版本。
- ❌ **3D 宠物**：生成接口曾预留，非当前重心。
- ❌ **更多工具（Cursor/Gemini 等）**：保持 Claude Code + Codex；适配层抽象好，扩展零侵入（见 §3.4）。

> 各版本更细的非目标见对应 spec 的"非目标"小节。

### 2.4 发布与商业模式（Distribution & Monetization）

- **分发渠道**：计划上架 **Mac App Store**。
- **付费模式**：**买断制（一次性付费）**，无订阅、无内购账号体系——与 §2.3"纯本地、无服务器、无登录"一致（买断不引入云端账号或服务器依赖）。
- **已知约束/风险**：App Store 强制 **App Sandbox**，与当前架构存在真实张力——hook 二进制写 `~/.codex`/`~/.claude`、Unix domain socket、osascript 终端跳回均属沙盒外系统副作用。上架前需评估：沙盒豁免（temporary-exception entitlements）/ 迁移到 App Group 容器路径，或退而采用 **Developer ID 公证直分发**作为兜底。该评估属独立工作项，**不改变 §5 现有 fail-open / 稳定路径 / 本地优先的工程约束**。

---

## 3. 组织架构（Architecture）

### 3.1 总体结构：单 Swift Package · 四 target

VibePet 是单一 Swift Package（`Package.swift`，swift-tools 6.0，macOS 14+），拆为四个职责单一、可独立测试的 target，外加一个基准工具：

| Target | 类型 | 职责 | UI 依赖 |
|---|---|---|---|
| `VibePetCore` | library | 数据模型、bridge 协议与 socket、工具适配层、安装器逻辑、持久化、几何计算。**所有可单测的纯逻辑都在这里。** | ❌ 禁止 AppKit/SwiftUI |
| `VibePetApp` | executable (app) | SwiftUI/AppKit 宿主：浮动宠物窗、菜单栏、设置页、气泡渲染、运行 `BridgeServer`。 | ✅ |
| `VibePetHooks` | executable (CLI) | 体积极小、启动极快的 hook 二进制。被各工具 hook 调用，转发事件、决策类阻塞等待、按工具格式输出。 | ❌ |
| `VibePetSetup` | executable (CLI) | 安装/卸载 hooks：拷贝 hook 二进制到稳定路径、幂等写入工具配置、备份、精确移除。 | ❌ |
| `CutoutBenchmark` | executable (tool) | 抠图质量基准工具（0.1 遗留，随抠图退役一并移除）。 | ❌ |

> **核心护栏**：`VibePetCore` 必须保持 UI 无关。osascript/AppKit 等系统副作用即便逻辑在 Core，也须经**可注入闭包**暴露，使单测不碰真实系统（见终端跳回 spec §8）。

### 3.2 双通道 Bridge（hook ↔ App）

hook 进程与宿主 App 通过 **Unix domain socket** 通信，路径固定在 `~/Library/Application Support/VibePet/bridge.sock`（目录 `0700`、套接字 `0600`，仅当前用户），消息为**行分隔 JSON**（newline-delimited）。

```
┌──────────────────────────────────────────────────────────────┐
│                        AI 编码工具                              │
│   Claude Code (settings.json)        Codex (config.toml)       │
│     PreToolUse / Stop / Notification / …  PermissionRequest /  │
│                                            notify / SessionStart│
└───────────────┬───────────────────────────┬──────────────────┘
                │ hook 命令（事件 JSON 经 stdin）               │
                ▼                                               ▼
        ┌───────────────────────────────────────────────┐
        │   VibePetHooks (CLI)                            │
        │   解析事件 → 归一化 BridgeEnvelope              │
        │   决策类：阻塞等待回传（超时 fail-open）        │
        │   通知类：fire-and-forget，立即 exit 0          │
        └───────────────┬───────────────────────────────┘
                        │ Unix domain socket (NDJSON)
                        ▼
        ┌───────────────────────────────────────────────┐
        │   VibePetApp                                    │
        │   BridgeServerHost ── decideStream/notifyStream │
        │        │                                        │
        │        ▼   apply(event)                         │
        │   SessionState reducer  ◀─ resolve ──┐ (0.2新增)│
        │        │ 派生                          │         │
        │        ▼                              │         │
        │   PetController(状态机) → PetView/气泡 ┘         │
        │   + StatusItemController(菜单栏聚合)            │
        └───────────────────────────────────────────────┘
```

**两条通道**（机制在 0.1 已建立，0.2 不改）：

- **决策通道（阻塞）**：`approval` / `question`。CLI 保持 socket 连接阻塞等待，App 弹可交互气泡，用户操作经同一连接回传，CLI 转成工具期望的 stdout JSON 后 `exit 0`。超时/无 App → `defer` fail-open。
- **通知通道（非阻塞）**：`completion` / `status` 及全部生命周期事件。CLI 发送后立即 `exit 0`，App 弹无按钮气泡数秒收起。

**0.2 新增的会话状态层**：App 侧引入持久 `SessionState` reducer 作为**单一事实源**。两条通道都喂它——通知 envelope 翻译成 `AgentEvent` 后 `apply`；决策 envelope 进入阻塞回路时置会话 `waitingForApproval/Answer`，用户 resolve 后置回 `running/completed`。宠物当前活动与菜单栏数字由 `SessionState` **派生**，不再由单个 envelope 直接决定。详见子项目 1 spec。

### 3.3 归一化数据模型（工具无关）

UI 只认一套规范模型、不感知工具差异；新增工具只需新增 adapter，渲染层零改动。核心信封 `BridgeEnvelope` 用 `BubbleContent` tagged enum 承载四种交互态：

- `approval`（允许/拒绝）、`question`（结构化多选）→ **需回传**（hook 阻塞等待）。
- `completion`（任务完成）、`status`（轻量状态）→ **通知**（非阻塞）。

0.2 在此之上增加**会话词汇** `AgentEvent`（`sessionStarted` / `activityUpdated` / `permissionRequested` / `questionAsked` / `sessionCompleted` / `jumpTargetUpdated` / `actionableStateResolved`）与 `SessionState` / `AgentSession` / `SessionPhase`，并给 `SourceInfo` 增补稳定 `sessionID` 与 `jumpTarget`。

### 3.4 工具适配层（ToolAdapter）

把每个工具的"事件格式 + 决策回写格式"差异封进各自 adapter，**新增工具 = 新增一个 adapter**，桥接与渲染层零侵入。

- `ClaudeCodeAdapter`：`PreToolUse → approval`、`AskUserQuestion → question`（经 `updatedInput` 预填回写）、`Stop → completion`、`Notification → status`；0.2 拓宽到全生命周期 hook → `AgentEvent`。
- `CodexAdapter`：`PermissionRequest → approval`、`notify(agent-turn-complete) → completion`；提问降级为"回终端处理"（纯 hook 限制）。

> 适配层是 VibePet 跨工具扩展性的关键抽象。

### 3.5 持久化与运行时目录

统一目录 `~/Library/Application Support/VibePet/`：

```
VibePet/
├── bin/VibePetHooks        # 稳定路径的 hook 二进制拷贝（工具配置指向此，与 .app 位置解耦）
├── pets/                   # 导入的宠物（0.2: Codex 格式文件夹；0.1: <uuid>/sprite.png 已退役）
├── config.json             # 活动宠物、启用工具、超时、宠物位置等
├── install-manifest.json   # 记录为哪些工具写入哪些 hook 条目 + 二进制版本
├── bridge.sock             # 运行时套接字
└── backups/                # 写入工具配置前的备份
```

宠物来源在 0.2 改为**多根聚合**：共享 `~/.codex/pets/<slug>/`（只读、原地引用）+ VibePet 导入目录（拖拽导入拷入），按 slug 去重（导入优先）。

---

## 4. 代码参考（Code Map）

> 按 target/模块组织，给关键文件锚点与作用；不逐文件展开（具体逻辑读源码与对应 spec）。
> **演进标注**：🟢 长期保留 · 🟡 0.2 将扩展/改造 · 🔴 0.2 将删除（抠图退役）· ✨ 0.2 新增（尚未落地）。

### 4.1 `VibePetCore/`（纯逻辑，可单测）

**Bridge/** — 桥接协议与传输 🟢
- `BridgeEnvelope.swift`：归一化信封 + `BubbleContent` 四态枚举；`SourceInfo` 已含稳定 `sessionID` 与可选 `jumpTarget`。🟢🟡
- `BridgeResponse.swift`：回传响应（`approval`/`question`/`defer`）。
- `BridgeServer.swift` / `BridgeClient.swift`：socket 服务端/客户端。
- `BridgeSocketIO.swift` / `SocketPath.swift`：NDJSON 收发与套接字路径。
- `HookRuntime.swift` / `HookInvocation.swift`：hook 运行时（`runDecision`/`runNotification`）、调用解析；已支持 lifecycle `AgentEvent` 随 envelope 送达。🟢🟡
- `HookSkipConfiguration.swift`：hook 跳过配置（post-M6 硬化，见 memory）。

**Adapters/** — 工具适配层 🟢🟡
- `ToolAdapter.swift`：适配协议（`parseEvent` / `parseAgentEvent` / `encodeResponse`）。
- `ClaudeCodeAdapter.swift` / `CodexAdapter.swift`：两工具适配。🟢🟡 已增 lifecycle hook → `AgentEvent` 映射与 `SourceInfo.sessionID` 填充；`JumpTarget` 环境解析仍待子项目 3。
- `RiskClassifier.swift`：审批风险分级启发式（危险命令模式 → high）。

**Install/** — 安装器逻辑 🟢🟡
- `HookInstaller.swift`：install/uninstall/status 三件套编排。
- `InstallManifest.swift`：manifest 驱动幂等与精确卸载。
- `ClaudeCodeConfigWriter.swift` / `CodexConfigWriter.swift`：写 `settings.json` / `config.toml`。🟢 已注册 0.2 lifecycle hook 条目并保留幂等/精确卸载。
- `BinaryInstaller.swift` / `InstallPaths.swift` / `HooksBinaryLocator.swift`：二进制拷贝到稳定路径、路径解析。
- `HookHealthCheck.swift`：安装健康检查（post-M6 硬化）。
- `ToolConfigWriter.swift`：写入器协议。

**Generation/** — 照片抠图管线 🔴（0.2 子项目 2 删除，已存档）
- `PetGenerator.swift`（协议+`PetAsset`）、`LocalCutoutGenerator.swift`（Vision 抠图）、`GenerationService.swift`（生成器选择）、`PetImportStateMachine.swift`（导入状态机）。

**Persistence/** — 持久化 🟢🟡
- `ConfigStore.swift` / `AppConfig.swift`：读写 `config.json`。
- `PetAssetStore.swift`：宠物素材管理。🟡 0.2 改为多根聚合读取器（slug 去重、旧 UUID 格式忽略）。
- `SupportDirectory.swift`：Application Support 目录定位。

**Geometry/** — 纯几何 🟢
- `BubbleAnchor.swift`：象限感知锚定 + 边界避让 + 尾巴跟踪。
- `ScreenSnap.swift`：拖动软吸附/贴边。
- `SpriteHitMask.swift`：逐像素 alpha 命中（透明穿透）。🟡 0.2 改为对"当前帧"alpha 建掩码。

**Pet/** — 宠物状态机 🟢
- `PetStateMachine.swift`：`idle/greet/notify/decide` 状态机（UI 无关部分）。

**Session/** — 会话模型 🟢
- `SessionState.swift` / `SessionModels.swift` / `AgentEvent.swift`：持久多会话 reducer、`AgentSession`、`SessionPhase`、`JumpTarget` 数据模型、派生聚合与探活 reaping。

**✨ 0.2 将新增（尚未落地）**：hook 时终端 locator（osascript 经注入闭包）、Codex `pet.json` 解析 + spritesheet 网格切片逻辑。

### 4.2 `VibePetApp/`（SwiftUI/AppKit 宿主）

- `main.swift`：App 入口。
- **Bridge/**`BridgeServerHost.swift`：socket 服务宿主，`decideStream`/`notifyStream`。🟢🟡 已接 App-owned `SessionState`、决策转移与探活 sweep。
- **Pet/**`PetController.swift`（状态协调，已由 `SessionState` 派生活动）、`PetView.swift`（渲染）、`PetAnimations.swift`（程序化动画 🔴 0.2 由 `SpriteSheetAnimator` ✨ 替换）、`PetWindowSurface.swift`。
- **Bubble/**`SpeechBubble.swift`、`ApprovalCard.swift`、`QuestionCard.swift`、`BubbleStackView.swift`、`BubbleQueue.swift`（堆叠队列）、`BubbleTheme.swift`。🟡 0.2 气泡加双击跳回。
- **Window/**`PetWindow.swift`、`PetWindowController.swift`、`PetDragController.swift`：透明无边框浮动窗、拖动吸附。
- **MenuBar/**`StatusItemController.swift`：菜单栏。🟢🟡 已展示多会话活跃/待处理聚合数。
- **Settings/**`SettingsView.swift`、`HookInstallSection.swift`、`HookInstallCoordinator.swift`：设置页与安装编排。
- **Onboarding/**`OnboardingFlow.swift`：首启引导。🟡 0.2 第②步"生成宠物"→"挑一个宠物"。
- **Import/**`PetImportPanel.swift`、`PetImportViewModel.swift`：照片导入面板 🔴（0.2 删除，导入改为宠物文件夹拖拽）。
- **Support/**`ImageLoading.swift`：URL→CGImage。
- **✨ 0.2 将新增**：`SpriteSheetAnimator`（精灵渲染）、`TerminalJumpService` + `TerminalJumpTargetResolver`（终端跳回，AppKit/osascript/socket/CLI）。

### 4.3 `VibePetHooks/` · `VibePetSetup/`

- `VibePetHooks/main.swift` 🟢：hook CLI 入口，读 stdin → adapter → 连 socket → 决策阻塞/通知即走。
- `VibePetSetup/main.swift` 🟢：安装器 CLI（install/uninstall/status 子命令）。

### 4.4 测试（`Tests/`）

- `Tests/VibePetCoreTests/`：核心逻辑单测（编解码往返、adapter 解析/回写、风险分级、配置/资产读写、抠图——🔴 抠图相关随退役移除）。
- `Tests/VibePetSetupTests/`：安装器单测（幂等、manifest 往返、精确卸载、Codex trust、路径转义、健康检查）。
- `Tests/VibePetAppTests/`：App 层（审批卡、气泡队列、安装协调、通知流）。
- `Tests/E2E/`：端到端（审批/提问/通知/Codex 审批流）。
- `Tests/Fixtures/`：固定 fixture（`claude/` 事件样例；`photos/` 🔴 抠图退役移除）。

> **测试纪律**：安装/配置写入类逻辑**仅单测、不做真实安装冒烟**——即便覆盖 `$HOME`，写入仍会命中真实 `~/.codex`/`~/.claude`（见 memory `no-real-installer-smoke-tests`）。`swift test` 偶发 SIGPIPE（signal 13）非回归，可重跑或 `--filter`。

---

## 5. 技术方案（横切关注点 Cross-cutting）

> 这些是跨功能、跨版本都成立的工程原则与机制，是 VibePet 的"地基约束"。具体某功能如何套用见对应 spec。

### 5.1 Fail-open（红线，不可退化）

**VibePet 任何异常都不得阻塞用户的 AI 工具。** 这是最高优先级约束：

- App 未运行 / socket 连接失败 / 输入畸形 / socket 损坏：CLI ≤ 2s 输出 `defer`（Claude：无 JSON 的 `exit 0`；Codex：decline），工具回退**原生流程**。
- App 已连接但用户未响应：按决策倒计时（默认 20s，可配）到点 `defer`。
- **工具侧 hook timeout 必须 > VibePet 倒计时 + 缓冲**；安装器检测到不满足则拒绝写入该组合。
- 终端跳回 locator / osascript 任何失败一律返回 nil 退化，绝不阻塞 hook。
- reducer 容错：未知会话/事件忽略，解析失败丢弃不抛；进程探活兜底清理"卡住可见"的会话。

任何新功能落地前都要自问：失败时是否仍 fail-open？

### 5.2 本地优先（Local-first）

抠图（0.1）、宠物聚合、精灵渲染全程本地，照片/宠物素材不出本机。**不新增网络生成、遥测、上传路径**，除非有显式产品变更与用户授权设计（`CLAUDE.md` 护栏）。0.2 的 Codex 宠物来源是本地文件系统读取，无在线安装。

### 5.3 hook 二进制稳定路径（关键）

工具配置注册的 hook command **不指向 `.app` 包内路径**，而指向 `~/Library/Application Support/VibePet/bin/VibePetHooks`（安装时拷贝）。原因：`.app` 改名/移动/重装会让包内绝对路径失效、已注册 hooks 全断。拷到固定路径后，hook 路径与 app 安放位置解耦。

> **路径含空格**：稳定安装路径含空格且经 `/bin/sh -c` 执行，配置写入器必须**单引号转义** hook 命令路径（见 memory `hook-command-paths-need-shell-quoting`）。

### 5.4 安装器：manifest 驱动 · 幂等 · 可精确卸载

安装/卸载靠一份 `install-manifest.json` 驱动，而非字符串猜测哪条配置是自己写的：

- **install**：写前展示将改动的文件/二进制/备份并经确认 → 备份原配置 → 拷贝/升级 `bin/VibePetHooks` → 幂等写入 hook 条目（指向稳定路径）→ 写 manifest。
- **uninstall**：读 manifest，只移除 `writtenHooks` 记录的条目，**保留用户其它 hooks**。
- **status**：读 manifest + 校验二进制版本 + 激活状态 → `未安装 / 已写入待信任 / 已启用 / 版本落后`。
- **Codex trust**：Codex hook 可能需用户在 `/hooks` 中 review/trust；"已写入" ≠ "已生效"，安装态区分 `installedNeedsTrust` / `trustedActive`，并把首次真实收到 Codex 事件作为激活证据。
- **不假设独占**：多来源 hook 可能并发，所有回写幂等，`requestId` 仅用于自身配对、不作全局锁。


### 5.5 测试策略（贯穿各版本）

- **单元测试（Core，无 UI）**：编解码往返、adapter 解析/回写、reducer 事件序列 → 期望状态、风险分级、配置/资产读写、安装器幂等/卸载。所有系统副作用经注入闭包，单测不碰真实系统。
- **端到端（脚本化）**：喂 hook CLI 事件，断言气泡延迟 ≤ 500ms、deny/allow 回写正确、fail-open ≤ 2s / 倒计时。
- **手动验收（Demo）**：真实工具会话触发决策 → 气泡弹出 → 点拒绝 → 工具取消。
- **回归红线**：任何版本不得让既有决策阻塞回路与 fail-open 行为退化。

### 5.6 关键 API 依据

| 能力 | 文档 |
|---|---|
| Claude Code Hooks（`permissionDecision`、`updatedInput`、生命周期 hook） | https://code.claude.com/docs/en/hooks-guide |
| Codex Hooks（`PermissionRequest`、`notify`） | https://developers.openai.com/codex/hooks |
| Codex 宠物格式（`pet.json` + spritesheet） | inspect 真实 `~/.codex/pets/<slug>/`；petdex sidecar 事件→状态映射 |
| Apple Vision 主体抠图（0.1 退役） | WWDC 2023 "Lift subjects from images in your app" |
| macOS 浮动透明窗口 / NSStatusItem / osascript 自动化 | Apple Developer Documentation |

---

## 6. 风险与路线图（Risks & Roadmap）

### 6.1 长期技术风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| Claude Code `allow` 抑制原生弹窗存在版本相关 bug | "允许"路径可能仍弹原生确认 | `deny` 路径可靠优先保障；`allow` 尽力而为并在文档标注；fail-open 兜底 |
| `updatedInput` / `allowAlways` schema 随版本漂移 | 气泡内答题/始终允许可能失效 | 实现前做 schema spike + fixture 固化；未验证则降级回终端处理 |
| Codex hook 需 trust 且多来源并发 | 安装后可能未生效、不能独占审批流 | 安装态区分待信任/已启用；回写幂等、可并发；真实事件作激活证据 |
| 阻塞型 hook 等待导致 Agent 卡顿 | 可用性 | ≤2s/倒计时 fail-open；工具 timeout > VibePet 倒计时 |
| `SessionEnd` 不到达导致"卡住可见"会话 | 宠物/菜单栏状态失真 | 进程探活兜底清理（连续 N 次未见 → ended） |
| 不同画廊 Codex 宠物行序/字段差异 | 精灵动画错位 | `pet.json` 声明优先 + canonical 兜底顺序；非法宠物跳过 |
| 终端 locator 触发 macOS 自动化权限弹窗 | 首次精度/体验 | 全程 fail-open，拒绝即退化为 env+tty，不报错 |
| 置顶窗口在全屏/多 Space 表现异常 | 宠物被遮挡 | 合适窗口层级与 collectionBehavior；全屏场景验证 |
| 参考项目 open-vibe-island 架构对齐 | 实现效率 | 可自由查阅其源码作架构与实现参考；按 VibePet 自有模型/命名落地 |

### 6.2 路线图

- **0.1 MVP（已归档）**：本地抠图 2D 宠物 · 浮动窗 + 待机/打招呼 · 菜单栏 · Claude Code + Codex 四态气泡 · 安装/卸载 CLI。详见 `docs/archive/`。
- **0.2（当前）**：① 会话模型 + 全 hook 生命周期 → ② Codex spritesheet 宠物宿主（退役抠图）+ 精灵动画 → ③ 终端跳回。三子项目顺序依赖，①是②③的共同地基。详见 `docs/superpowers/specs/`。
- **后续候选**（未承诺）：App 内宠物画廊浏览 · 会话状态跨重启持久化 · 更多工具（Cursor/Gemini）· 完成气泡"回复 Agent" · 更丰富情绪/皮肤 · 可选 notch UI。

---

## 7. 维护本文档的约定

- 本文只增改"跨版本稳定"的内容；**功能点、验收标准、里程碑不写进来**，留在 specs。
- 发新版本时：更新 §1.3 产品定位、§2.2 演进表、§3 架构演进、§4 代码锚点与演进标注、§6.2 路线图；并在 §0 更新 specs/archive 索引。
- §4 代码参考的演进标注（🟢🟡🔴✨）应随实现推进刷新——✨ 落地后转 🟢/🟡，🔴 删除后从表中移除并指向 archive。
- 与 `CLAUDE.md` 项目护栏保持一致；二者冲突时以 `CLAUDE.md`（用户指令）为准。
