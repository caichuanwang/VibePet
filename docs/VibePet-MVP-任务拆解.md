# VibePet MVP 任务拆解（Task Breakdown）

> 版本：v0.1（MVP）
> 日期：2026-06-17
> 配套文档：[《VibePet 技术实现方案》](./VibePet-技术实现方案.md)（里程碑见其 §9）、[《VibePet PRD》](./VibePet-PRD.md)（用户故事见 §2.2、KPI 见 §1）

本文把技术方案 §9 的 7 个里程碑（M0–M6）拆成**中粒度、可独立提交**的 task。每个 task 对应一次可验收的提交/PR，带三个字段：

- **验收标准** —「做完」的客观判据，尽量绑定 PRD 用户故事（US-x）、KPI 或单元测试。
- **依赖** — 必须先完成的 task id（跨里程碑也标出）；标 `无` 表示可立即开始。
- **涉及文件/类型** — 预期改动的源文件路径与核心类型，路径基于技术方案 §1.1 的 target 划分与 §6 的目录约定。

> Task id 形如 `M0-1`。路径前缀对应 target：`VibePetCore/`、`VibePetApp/`、`VibePetHooks/`、`VibePetSetup/`、`Tests/`。

---

## 目录

- [M0 · 脚手架与 Bridge 数据模型](#m0--脚手架与-bridge-数据模型)
- [M1 · 本地生成管线](#m1--本地生成管线)
- [M2 · 桌面宠物窗](#m2--桌面宠物窗)
- [M3 · Bridge 通知链路](#m3--bridge-通知链路)
- [M4 · 审批闭环](#m4--审批闭环)
- [M5 · 提问闭环](#m5--提问闭环)
- [M6 · Codex 适配 + 安装器 + 发布打磨](#m6--codex-适配--安装器--发布打磨)
- [关键路径与并行建议](#关键路径与并行建议)
- [技术债与后续跟踪（Code Review）](#技术债与后续跟踪code-review)

---

## M0 · 脚手架与 Bridge 数据模型

> 里程碑目标：可编译、可单测的工程骨架与全部归一化数据模型就位。退出标准见技术方案 §9/M0。

### M0-1 · Swift Package 与四 target 骨架

- **验收标准**：`swift build` 通过；四个 target（`VibePetCore` library、`VibePetApp`/`VibePetHooks`/`VibePetSetup` executable）均生成产物；`VibePetApp` 能空跑起一个最小窗口。CI 中 `swift build && swift test` 可运行（即便 test 暂空）。
- **依赖**：无。
- **涉及文件/类型**：`Package.swift`；各 target 入口 `VibePetApp/VibePetApp.swift`、`VibePetHooks/main.swift`、`VibePetSetup/main.swift`；`Tests/` 目录骨架。

### M0-2 · Bridge 信封与气泡内容模型

- **验收标准**：`BridgeEnvelope` / `SourceInfo` / `ToolKind` / `BubbleContent`（四 case：`approval`/`question`/`completion`/`status`）及各 Content 结构（`ApprovalContent`/`QuestionContent`/`CompletionContent`/`StatusContent`/`ActionPreview`/`AlwaysAllowOption`/`RiskLevel`）按技术方案 §3.2 定义；`BubbleContent.needsResponse` 行为正确（approval/question→true，completion/status→false）。编解码往返单测全绿（§8.1 第 1 条）。
- **依赖**：M0-1。
- **涉及文件/类型**：`VibePetCore/Bridge/BridgeEnvelope.swift`（含上述全部类型）；`Tests/VibePetCoreTests/BridgeEnvelopeCodecTests.swift`。

### M0-3 · Bridge 响应模型

- **验收标准**：`BridgeResponseEnvelope` / `BridgeResponse`（`approval`/`question`/`defer`）/ `ApprovalDecision`（`allowOnce`/`allowAlways`/`deny`）/ `QuestionAnswer` 按 §3.3 定义；`requestId` 配对字段就位；编解码往返单测全绿。
- **依赖**：M0-2。
- **涉及文件/类型**：`VibePetCore/Bridge/BridgeResponse.swift`；`Tests/VibePetCoreTests/BridgeResponseCodecTests.swift`。

### M0-4 · ToolAdapter 协议

- **验收标准**：`ToolAdapter` 协议按 §4 定义（`tool` / `parseEvent(stdin:env:)` / `encodeResponse(_:for:)`）；可被 mock 实现并通过编译；协议方法签名与 M0-2/M0-3 的模型对齐。
- **依赖**：M0-2、M0-3。
- **涉及文件/类型**：`VibePetCore/Adapters/ToolAdapter.swift`；`Tests/VibePetCoreTests/ToolAdapterMockTests.swift`。

### M0-5 · Unix socket 收发基础设施

- **验收标准**：`BridgeServer` 监听 `~/Library/Application Support/VibePet/bridge.sock`（目录 0700、套接字 0600，§3.1）；`BridgeClient` 连接并完成一次 newline-delimited JSON 往返；App 启动时清理并重建残留 socket（§7）；连接失败路径返回明确错误。本地往返集成测试通过。
- **依赖**：M0-2、M0-3。
- **涉及文件/类型**：`VibePetCore/Bridge/BridgeServer.swift`、`VibePetCore/Bridge/BridgeClient.swift`、`VibePetCore/Bridge/SocketPath.swift`；`Tests/VibePetCoreTests/BridgeRoundTripTests.swift`。

### M0-6 · ConfigStore 骨架

- **验收标准**：`ConfigStore` 读写 `config.json`（活动宠物 `activePetID`、启用工具、决策超时、生成器 ID、宠物位置等字段，§6）；文件不存在时返回默认配置；读写往返单测通过。
- **依赖**：M0-1。
- **涉及文件/类型**：`VibePetCore/Persistence/ConfigStore.swift`、`VibePetCore/Persistence/AppConfig.swift`；`Tests/VibePetCoreTests/ConfigStoreTests.swift`。

---

## M1 · 本地生成管线

> 里程碑目标：脱离 UI，离线把照片抠成透明精灵 PNG。对应 US-1、抠图 KPI。

### M1-1 · PetGenerator 协议与 PetAsset 模型

- **验收标准**：`PetGenerator` 协议（`identifier` / `generate(from:progress:)`）、`PetAsset`、`PetKind`（`sprite2D`/`stylized2D`/`model3D`）、`PetLayer`、`GenError`（含 `.noSubject`）按 §2 定义并通过编译；`PetAsset` 可 Codable 往返。
- **依赖**：M0-1。
- **涉及文件/类型**：`VibePetCore/Generation/PetGenerator.swift`（含 `PetAsset`/`PetKind`/`GenError`）；`Tests/VibePetCoreTests/PetAssetCodecTests.swift`。

### M1-2 · LocalCutoutGenerator（Vision 抠图）

- **验收标准**：用 `VNGenerateForegroundInstanceMaskRequest` 抠出主体（§2.1）；多主体时取面积最大者（`largestInstance`）；`croppedToInstancesExtent` 裁到主体范围；无显著主体抛 `GenError.noSubject`；输出带透明通道的 PNG；`progress` 回调被调用。给定单主体测试图能产出非空透明精灵。
- **依赖**：M1-1。
- **涉及文件/类型**：`VibePetCore/Generation/LocalCutoutGenerator.swift`；`Tests/VibePetCoreTests/LocalCutoutGeneratorTests.swift`（含测试用图 fixtures）。

### M1-3 · PetAssetStore 资源持久化

- **验收标准**：`PetAssetStore` 把精灵写入 `pets/<uuid>/sprite.png` + `meta.json`（§6）；可按 id 读取/列举/删除；切换不影响其它宠物素材；读写往返单测通过。
- **依赖**：M1-1。
- **涉及文件/类型**：`VibePetCore/Persistence/PetAssetStore.swift`；`Tests/VibePetCoreTests/PetAssetStoreTests.swift`。

### M1-4 · GenerationService 选择器

- **验收标准**：`GenerationService` 依据 `config.activeGeneratorID` 从注册表取 `PetGenerator`，对外只暴露 `generate(from:)`（§2.3）；MVP 注册 `LocalCutoutGenerator`；未知 id 有明确兜底/报错；新增生成器只需注册、不改调用方。
- **依赖**：M1-1、M1-2、M0-6。
- **涉及文件/类型**：`VibePetCore/Generation/GenerationService.swift`；`Tests/VibePetCoreTests/GenerationServiceTests.swift`。

### M1-5 · 离线生成质量基准脚本

- **验收标准**（对应抠图 KPI）：脚本对固定 20 张测试照片集跑 `LocalCutoutGenerator`，照片需带 `clearSubject` / `edgeHard` / `lowContrast` / `multiSubject` 标签；记录每张耗时并汇总 P50/P95，输出供人工边缘打分的结果（§8.2）；运行后可判定 P50 ≤ 3s、P95 ≤ 8s、清晰主体子集可用率 ≥ 90% / 全量 ≥ 80%，并列出各标签分母。
- **依赖**：M1-2、M1-3。
- **涉及文件/类型**：`Tests/Benchmarks/CutoutBenchmark.swift` 或独立可执行 `Tools/CutoutBenchmark/`；测试照片集 `Tests/Fixtures/photos/`。

---

## M2 · 桌面宠物窗

> 里程碑目标：宠物"活"在桌面——透明浮动、动画、拖动吸附、菜单栏、导入面板。对应 US-1 / US-2 / US-0①②。

### M2-1 · 透明浮动 NSWindow

- **验收标准**（对应 US-2）：无边框、`isOpaque=false`、`backgroundColor=.clear`、`level=.floating`、`collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]`（§5.1）；透明区域鼠标穿透、仅宠物本体命中响应（`ignoresMouseEvents` 按区域控制）；默认精灵框 120×120pt。
- **依赖**：M0-1。
- **涉及文件/类型**：`VibePetApp/Window/PetWindow.swift`、`VibePetApp/Window/PetWindowController.swift`。

### M2-2 · 宠物视图与待机/打招呼动画

- **验收标准**（对应 US-1/US-2）：SwiftUI 宠物视图加载 `PetAsset` 精灵；待机呼吸（squash/stretch）+ 轻微晃动；若 `layers` 提供则叠加眨眼、否则跳过（§2.1 末）；打招呼动画；遵守"减弱动态效果"（Reduce Motion）改用淡入淡出（§5.3 通用）。
- **依赖**：M2-1、M1-1。
- **涉及文件/类型**：`VibePetApp/Pet/PetView.swift`、`VibePetApp/Pet/PetAnimations.swift`。

### M2-3 · 拖动、软吸附与位置持久化

- **验收标准**（对应 US-2）：基于 `NSScreen.main.visibleFrame` 定位（§5.1.1）；首启落右缘内缩 24pt、贴底；可拖到屏内任意处，`mouseUp` 时最近边距 < 40pt 则动画吸附（内缩 8pt）并保留沿边坐标；位置始终 clamp 进 `visibleFrame`；位置存 `config.json`，启动时若 `visibleFrame` 变化则 clamp 回。
- **依赖**：M2-1、M0-6。
- **涉及文件/类型**：`VibePetApp/Window/PetDragController.swift`、`VibePetApp/Window/ScreenSnap.swift`；复用 `ConfigStore`。

### M2-4 · 菜单栏（NSStatusItem）

- **验收标准**（对应 US-2）：菜单项含显示/隐藏宠物、切换宠物、导入新照片、打开设置、退出（§5.4）；各项行为正确接线。
- **依赖**：M2-1。
- **涉及文件/类型**：`VibePetApp/MenuBar/StatusItemController.swift`。

### M2-5 · 导入→生成面板（PetImportPanel）

- **验收标准**（对应 US-1）：单一紧凑面板，状态机 `idle→generating→result→placed`，错误转 `error`（§5.5）；接受拖拽/选择 JPG/PNG/HEIC，**导入即自动抠图**（无独立生成按钮）；`generating` 显示由 `progress` 回调驱动的进度；`result` 棋盘格预览透明精灵 + 可选命名（预填占位名可跳过）；确认后写入 `PetAssetStore` 与 `config.activePetID`，宠物落右下角进入待机；`error`（如 `.noSubject`）给可读提示 + 换一张/重试，不产生半成品资源（§7）。
- **依赖**：M1-4、M1-3、M2-2、M2-3。
- **涉及文件/类型**：`VibePetApp/Import/PetImportPanel.swift`、`VibePetApp/Import/PetImportViewModel.swift`。

### M2-6 · 首启 Onboarding 骨架（①欢迎 ②生成宠物）

- **验收标准**（对应 US-0 ①②）：首启依次引导 欢迎 → 生成宠物（复用 `PetImportPanel`）；仅首启出现，完成后宠物落桌面进入待机；第③步（安装 hooks）留占位、在 M6 接入。
- **依赖**：M2-5。
- **涉及文件/类型**：`VibePetApp/Onboarding/OnboardingFlow.swift`；复用 `PetImportPanel`、`ConfigStore`（首启标记）。

---

## M3 · Bridge 通知链路

> 里程碑目标：打通 hook CLI ↔ App 通道，先跑通非阻塞通知态。对应 US-4。

### M3-1 · VibePetHooks CLI 骨架（读 stdin → adapter → 发送）

- **验收标准**：CLI 从 stdin 读工具事件 JSON，经选定 `ToolAdapter` 归一化为 `BridgeEnvelope`，连 socket 发送（§1.1、§3.4）；连接不上立即 `defer` 退出（fail-open 雏形，§7）；二进制体积小、启动快。
- **依赖**：M0-4、M0-5。
- **涉及文件/类型**：`VibePetHooks/main.swift`、`VibePetHooks/HookRuntime.swift`；复用 `BridgeClient`/`ToolAdapter`。

### M3-2 · App BridgeServer 路由与 PetController 状态机

- **验收标准**：App 启动运行 `BridgeServer`，收到 envelope 后路由到 `PetController`；状态机 `idle/greet/notify/decide` 按 §5.2 流转；本里程碑跑通 `idle↔greet↔notify`（`decide` 留 M4）。
- **依赖**：M0-5、M2-2。
- **涉及文件/类型**：`VibePetApp/Pet/PetController.swift`、`VibePetApp/Bridge/BridgeServerHost.swift`。

### M3-3 · SpeechBubble 渲染 status / completion + 通用锚定

- **验收标准**（对应 US-4）：`SpeechBubble` 渲染 `.status`（单行图标+文本，6–8s 自动收起、悬停暂停）与 `.completion`（Markdown 摘要约 6 行后内部滚动，`isError` 用警示配色，8–10s 自动收起）（§5.3.1–5.3.2）；象限感知锚定 + 尾巴跟踪 + 边界避让 + 宽度 240–380pt（§5.3 通用）；头部显示来源 `工具·项目名·会话短id`；VoiceOver 标签。MVP 不含"回复 Agent"。
- **依赖**：M3-2。
- **涉及文件/类型**：`VibePetApp/Bubble/SpeechBubble.swift`、`VibePetApp/Bubble/BubbleAnchor.swift`、`VibePetApp/Bubble/BubbleTheme.swift`。

### M3-4 · ClaudeCodeAdapter — Stop / Notification 解析

- **验收标准**（对应 US-4，§8.1）：给定样例 `Stop` 事件 → `.completion`，优先提取 payload 中的 summary / transcript 摘要；若样例不含可展示摘要则生成可读兜底文案；`Notification` → `.status`（单行）；解析单测断言归一化为正确 `BubbleContent`。
- **依赖**：M0-4。
- **涉及文件/类型**：`VibePetCore/Adapters/ClaudeCodeAdapter.swift`（解析部分）；`Tests/VibePetCoreTests/ClaudeCodeAdapterParseTests.swift`。

### M3-5 · 通知链路端到端联调

- **验收标准**（对应 US-4、Fail-open 雏形）：喂 `VibePetHooks` 一条 `Stop`/`Notification` 事件 → App 运行态下宠物头顶弹无按钮气泡并自动收起；App 未运行时 CLI ≤ 2s `defer` 退出。
- **依赖**：M3-1、M3-2、M3-3、M3-4。
- **涉及文件/类型**：`Tests/E2E/NotificationFlowTests.swift`（脚本化喂 stdin，§8.3）。

---

## M4 · 审批闭环（Claude Code PreToolUse）

> 里程碑目标：MVP 核心价值——决策操作在气泡里一键允许/拒绝并真实回传。对应 US-3、端到端闭环/延迟 KPI、Fail-open KPI。

### M4-1 · ClaudeCodeAdapter — PreToolUse → approval 解析

- **验收标准**（§8.1）：`PreToolUse`（`tool_name`≠AskUserQuestion）→ `.approval`；从 `tool_input` 组装 `ActionPreview`：`Bash`→`.command`、`Edit/Write`→`.fileChange`、`Read`→`.fileRead`、`WebFetch`→`.network`；`alwaysAllow` 用 `tool_name` 填充（§4.1）。Bash/Edit/Read/WebFetch 样例事件解析单测全绿。
- **依赖**：M3-4。
- **涉及文件/类型**：`VibePetCore/Adapters/ClaudeCodeAdapter.swift`（PreToolUse 解析）；`Tests/VibePetCoreTests/ClaudeCodeApprovalParseTests.swift`。

### M4-2 · 风险分级启发式

- **验收标准**（§8.1）：按工具名+命令模式判定 `RiskLevel`；危险模式（`rm -rf`、`sudo`、`curl … | sh`、`git push --force`）→ `.high`；规则可配置、可单测；分级用例断言正确。
- **依赖**：M4-1。
- **涉及文件/类型**：`VibePetCore/Adapters/RiskClassifier.swift`；`Tests/VibePetCoreTests/RiskClassifierTests.swift`。

### M4-3 · ClaudeCodeAdapter — 审批决策回写

- **验收标准**（§8.1）：`deny` → `{"hookSpecificOutput":{...,"permissionDecision":"deny","permissionDecisionReason":...}}`；`allowOnce` → `permissionDecision:"allow"`；`defer` → 不输出 JSON、`exit 0`（§4.1、§7）。`allowAlways` 仅在 M4-3a schema spike 通过时启用；未通过时 adapter 不生成 `alwaysAllow`。回写字节与 exit 语义单测全绿。
- **依赖**：M4-1。（建议拆两步 PR：deny/allowOnce 不依赖 M4-3a 结论可先提交；allowAlways 分支等 M4-3a spike 结论后再合入，避免 spike 失败时返工。）
- **涉及文件/类型**：`VibePetCore/Adapters/ClaudeCodeAdapter.swift`（encodeResponse）；`Tests/VibePetCoreTests/ClaudeCodeEncodeTests.swift`。

### M4-3a · Claude allowAlways schema spike

- **验收标准**：用当前 Claude Code 版本的官方文档/本机 hook fixture 验证 `allowAlways` 或等价持久/会话权限规则的可落地方式；产出最小 fixture 与单测。若无法验证，记录为不支持，MVP 隐藏"始终允许"按钮，后续任务不得把 `allowAlways` 作为硬依赖。
- **依赖**：M4-1。
- **涉及文件/类型**：`Tests/Fixtures/claude/`；`Tests/VibePetCoreTests/ClaudeCodeAllowAlwaysSpikeTests.swift`；必要时更新 `VibePetCore/Adapters/ClaudeCodeAdapter.swift`。

### M4-4 · CLI 阻塞回路与 fail-open 超时

- **验收标准**（对应 Fail-open KPI，§3.4、§8.3）：决策类事件下 CLI 发送后保持连接等待 `BridgeResponseEnvelope`（用户响应倒计时默认 20s 可配，且小于工具 hook timeout）；收到→按 adapter 回写 stdout→`exit 0`；App 未运行/连接失败/socket 损坏→`defer` fail-open 且 ≤2s 退出，成功率 100%；App 已连接但用户未响应→默认 20s 到点后 `defer`。
- **依赖**：M3-1、M4-3。
- **涉及文件/类型**：`VibePetHooks/HookRuntime.swift`（阻塞等待+超时）；`VibePetCore/Bridge/BridgeClient.swift`（等待回传 API）。

### M4-5 · PetController.decide 态与审批气泡

- **验收标准**（对应 US-3）：`decide` 态高亮提醒 + 审批气泡三段布局（头部来源+风险 / 主体 `ActionPreview` 紧凑渲染 / 底部倒计时+按钮，§5.3.3）；按 `risk` 设配色与默认焦点（`.high` 默认焦点"拒绝"、`allow` 需明确点击）；按钮 拒绝(esc)/允许一次(⌘↩)/始终允许(仅 `alwaysAllow≠nil`)；危险命令标红、命令超 3 行截断；倒计时到点 fail-open 并提示。
- **依赖**：M3-3（M4-2 建议同步完成但不阻塞气泡骨架；气泡骨架以 `.medium` 风险默认渲染，M4-2 完成后直接集成配色与默认焦点，无需改骨架）。
- **涉及文件/类型**：`VibePetApp/Pet/PetController.swift`（decide）、`VibePetApp/Bubble/ApprovalCard.swift`。

### M4-6 · 回传通路与 requestId 配对

- **验收标准**：App 经同一阻塞连接回传 `BridgeResponseEnvelope`，`requestId` 与请求配对（§3.3、§3.4）；点"拒绝"→回 `deny`、点"允许一次"→回 `allowOnce`；M4-3a 通过时，"始终允许"→`allowAlways(scopeHint)`，否则不显示该按钮。
- **依赖**：M4-5、M0-5。
- **涉及文件/类型**：`VibePetApp/Bridge/BridgeServerHost.swift`（回传）、`VibePetApp/Pet/PetController.swift`。

### M4-7 · 队列与并发堆叠

- **验收标准**（对应 US-3、§5.3.5）：多个需回传气泡以 `requestId` 独立；卡牌堆叠+露头（身后最多 2 张露细边，顶显"还有 N 个待处理"）；FIFO，最早到达者在顶层；露头卡各自倒计时、超时静默 `defer` 并出栈；优先级 `decide` > `notify` > `greet`，`decide` 在场时通知仅累计小红点。
- **依赖**：M4-5。
- **涉及文件/类型**：`VibePetApp/Bubble/BubbleQueue.swift`、`VibePetApp/Bubble/BubbleStackView.swift`。

### M4-8 · 审批闭环端到端 Demo

- **验收标准**（对应端到端闭环 KPI、延迟 KPI、Fail-open KPI，§8.3/§8.4）：真实 Claude Code 会话触发需审批操作 → 气泡 ≤500ms 出现 → 点"拒绝"工具调用被真实取消、点"允许一次"放行；App 未运行/连接失败 ≤2s `defer`；App 已连接但用户未响应时默认 20s 倒计时后 `defer`。手动验收脚本（§8.4）跑通。
- **依赖**：M4-4、M4-6（M4-7 建议同步完成但不阻塞此 Demo；单气泡场景即可验收核心价值）。
- **涉及文件/类型**：`Tests/E2E/ApprovalFlowTests.swift`；安装到本机 `~/.claude/settings.json`（手动验收）。

---

## M5 · 提问闭环（AskUserQuestion）

> 里程碑目标：结构化多选题在气泡内作答，经 `updatedInput` 预填回工具。对应 US-3b。

### M5-0 · AskUserQuestion updatedInput schema spike

- **验收标准**：用当前 Claude Code 版本的官方文档/本机 hook fixture 验证 `AskUserQuestion` 的输入 schema、`updatedInput` 回写字段与抑制原生提问的实际行为；产出 fixture、最小回写样例与结论。若无法验证，M5 后续实现走降级路径：提醒 + 回终端处理，不承诺气泡内作答。
- **依赖**：M4-1、M4-4。（schema 研究阶段——查官方文档/读 hook 事件格式——仅需 M4-1 即可开始；M4-4 只在运行时验证"updatedInput 回写后原生提问被抑制"时才是硬前置。）
- **涉及文件/类型**：`Tests/Fixtures/claude/ask-user-question.json`；`Tests/VibePetCoreTests/ClaudeCodeQuestionSpikeTests.swift`。

### M5-1 · ClaudeCodeAdapter — AskUserQuestion → question 解析

- **验收标准**（§8.1）：`PreToolUse`（`tool_name`=AskUserQuestion）→ `.question`；从 `tool_input.questions` 映射 `QuestionItem`/`QuestionOption`（header/prompt/options/multiSelect/freeform，§4.1）；解析单测全绿。
- **依赖**：M5-0。
- **涉及文件/类型**：`VibePetCore/Adapters/ClaudeCodeAdapter.swift`（question 解析）；`Tests/VibePetCoreTests/ClaudeCodeQuestionParseTests.swift`。

### M5-2 · 提问气泡（QuestionCard）

- **验收标准**（对应 US-3b，§5.3.4）：逐题渲染 `QuestionItem`；单选用单选圈、`multiSelect` 用复选框；选项展示 `label`+次行灰字 `detail`；`allowsFreeform` 选中后展开文本框；提交(⌘↩) 汇集 `QuestionAnswer`（answers/freeform 按 header）；倒计时到点 fail-open。
- **依赖**：M5-1、M4-5。
- **涉及文件/类型**：`VibePetApp/Bubble/QuestionCard.swift`。

### M5-3 · updatedInput 预填回写

- **验收标准**（对应 US-3b，§4.1/§8.3）：M5-0 通过时，`question` 回传 → adapter 返回 `permissionDecision:"allow"` 且带 `updatedInput`，把答案预填进 AskUserQuestion 的 `answers`/`annotations`；工具拿到已填输入不再弹原生提问；未作答超时 → `defer` 回退原生提问。M5-0 未通过时，本任务验收降级输出：不写 `updatedInput`，改为提醒 + 回终端处理，且不阻塞原生提问。
- **依赖**：M5-1、M5-2、M4-4。
- **涉及文件/类型**：`VibePetCore/Adapters/ClaudeCodeAdapter.swift`（question encodeResponse）；`Tests/VibePetCoreTests/ClaudeCodeQuestionEncodeTests.swift`、`Tests/E2E/QuestionFlowTests.swift`。

---

## M6 · Codex 适配 + 安装器 + 发布打磨

> 里程碑目标：补齐第二工具、一键安装/卸载、设置页与发布打磨，达到可分发 MVP。对应 US-5 / US-3(Codex) / US-4(Codex) / US-0③。

### M6-1 · CodexAdapter — 解析

- **验收标准**（§8.1）：`PermissionRequest` → `.approval`（shell 升权/apply-patch → `.command`/`.fileChange`）；`notify(agent-turn-complete)` → `.completion`；提问/plan-mode 等需输入 → `.approval` 且 `requiresTerminalApproval=true`（降级，§4.2）。解析单测全绿。
- **依赖**：M4-1（复用 ActionPreview 组装）。
- **涉及文件/类型**：`VibePetCore/Adapters/CodexAdapter.swift`（解析）；`Tests/VibePetCoreTests/CodexAdapterParseTests.swift`。

### M6-2 · CodexAdapter — 回写与提问降级

- **验收标准**（对应 US-3 Codex，§4.2/§8.3）：`allowOnce`/`allowAlways` → allow（`allowAlways` 在 Codex MVP 中等同本次 allow，除非官方支持持久规则并经 fixture 验证）；`deny` → deny；`question` → `defer` + 引导回终端；MVP 只用 allow/deny/decline。回写逻辑需幂等，不假设 VibePet 是唯一匹配 hook；回写单测 + Codex 审批回路 E2E 通过。
- **依赖**：M6-1、M4-4。
- **涉及文件/类型**：`VibePetCore/Adapters/CodexAdapter.swift`（encodeResponse）；`Tests/VibePetCoreTests/CodexAdapterEncodeTests.swift`、`Tests/E2E/CodexApprovalFlowTests.swift`。

### M6-3 · requiresTerminalApproval 气泡形态

- **验收标准**（对应 US-3b Codex，§5.3.3 末）：`requiresTerminalApproval=true` 时审批气泡不显示允许/拒绝，改为单个"回终端处理"按钮 + 提示（MVP 仅聚焦/复制提示，真正跳转留 v1.1）；Codex 提问场景断言降级提示正确（§8.3）。
- **依赖**：M6-1、M4-5。
- **涉及文件/类型**：`VibePetApp/Bubble/ApprovalCard.swift`（降级分支）。

### M6-4 · VibePetSetup — 二进制拷贝到稳定路径

- **验收标准**（§1.2、US-5）：`install` 把 `VibePetHooks` 拷到 `~/Library/Application Support/VibePet/bin/VibePetHooks`（与 .app 解耦）；启动/安装校验版本，落后则重拷；工具配置 command 永远指向该拷贝路径、不引用包内路径。
- **依赖**：M3-1。
- **涉及文件/类型**：`VibePetSetup/BinaryInstaller.swift`、`VibePetSetup/Paths.swift`。

### M6-5 · VibePetSetup — manifest 驱动安装/卸载/status

- **验收标准**（对应 US-5，§4.3/§8.1）：`install` 幂等（已装跳过、版本落后仅重拷），写前展示将改动文件/二进制/备份并备份原配置，写 `install-manifest.json`；`uninstall` 按 manifest 精确移除 `writtenHooks` 条目、保留用户其它 hooks；`status` 返回 未安装/已写入待信任/已启用/版本落后；不覆盖用户非 VibePet 条目。对样例 `settings.json`/`config.toml`/`hooks.json` 的注入与精确移除单测通过（幂等、备份、Codex trust 状态）。
- **依赖**：M6-4、M6-1。
- **涉及文件/类型**：`VibePetSetup/HookInstaller.swift`、`VibePetSetup/InstallManifest.swift`、`VibePetSetup/ClaudeCodeConfigWriter.swift`、`VibePetSetup/CodexConfigWriter.swift`；`Tests/VibePetSetupTests/InstallerTests.swift`。

### M6-5a · Codex hook trust 激活态

- **验收标准**：Codex 写入后默认显示"已写入，待在 `/hooks` 信任"；设置页/CLI 给出可读引导；当 VibePet 首次收到真实 Codex hook 事件，manifest 或运行态缓存可标记为 `trustedActive`；无法自动判断时不得显示"已启用"。单测覆盖 `installedNeedsTrust → trustedActive` 状态转换。
- **依赖**：M6-5、M6-1。
- **涉及文件/类型**：`VibePetSetup/InstallManifest.swift`、`VibePetApp/Settings/HookInstallSection.swift`、`Tests/VibePetSetupTests/CodexHookTrustTests.swift`。

### M6-6 · 设置页与 onboarding ③（安装 hooks）

- **验收标准**（对应 US-5 / US-0③，§5.4）：设置页含 启用工具、一键安装/卸载（调 `VibePetSetup`、据 manifest 显示各工具安装态/版本/trust 状态）、决策超时、开机自启、生成器选择（MVP 仅本地）；onboarding 第③步只列检测到的工具（存在 `~/.claude/` 或 Codex 配置才显示）、各带安装态、可"以后再说"跳过、未检测到任何工具给可读提示；Codex 待信任时必须显示 `/hooks` 引导。
- **依赖**：M6-5a、M2-6。
- **涉及文件/类型**：`VibePetApp/Settings/SettingsView.swift`、`VibePetApp/Settings/HookInstallSection.swift`、`VibePetApp/Onboarding/OnboardingFlow.swift`（接入③）。

### M6-7 · 发布打磨（主题/错误/签名公证/基准达标）

- **验收标准**（§7/§8）：`BubbleTheme` 集中配色/圆角/字体、跟随明暗主题；错误提示按 §7 表统一；App 签名与公证完成；§8 全部测试通过、§1 全部 KPI 达标（端到端闭环、≤500ms、抠图时延/可用率、Fail-open 100%）。
- **依赖**：M6-2、M6-3、M6-6、M4-8、M5-3、M1-5、M4-3a、M4-7。
- **涉及文件/类型**：`VibePetApp/Bubble/BubbleTheme.swift`、`VibePetApp/Common/ErrorPresenter.swift`、`Scripts/notarize.sh`、CI 配置。

---

## 关键路径与并行建议

**关键路径（决定 MVP 完成时间）**：

```
M0-2 → M0-3 → M0-4/M0-5 → M3-1/M3-2 → M3-3 → M4-1
  → M4-3/M4-3a/M4-5 → M4-4/M4-6 → M4-8
  → M5-0 → M5 → M6-2/M6-5a → M6-7
```

**可并行的支线**：

- **生成管线（M1）** 仅依赖 M0-1，可与 M0-2~M0-6 及 M2 并行推进；M1-5 基准可最后补。
- **宠物窗（M2）** 的 M2-1/M2-2/M2-4 仅需 M0-1/M1-1，可早启动；M2-5 需 M1 管线就位。
- **风险分级（M4-2）**、**allowAlways spike（M4-3a）**、**队列堆叠（M4-7）** 是 M4 内可并行的独立模块；M4-3a 只 gate "始终允许"按钮，不 gate deny/allowOnce 主闭环。
- **AskUserQuestion spike（M5-0）** 应先于 M5 UI/回写实现；若失败，M5 走降级验收。
- **Codex 解析（M6-1）** 一旦 M4-1 完成即可起步，不必等审批闭环全部跑通。
- **Codex trust 激活态（M6-5a）** 可与设置页打磨并行，但 M6 发布验收必须能区分"已写入待信任"与"已启用"。

**里程碑级依赖**（与技术方案 §9 依赖图一致）：M0 → {M1, M3}；M2 ← {M0,M1}；M4 ← M3；M5 ← M4；M6 ← M5。

> 里程碑依赖图描述主干阻塞关系，具体启动时机以**任务级依赖**为准。典型示例：M4-1 仅需 M3-4，M3-4 仅需 M0-4，无需等待整个 M3 结束；M3-1/M3-4 仅需 M0-4/M0-5，可在 M2 并行推进时即启动。

---

## 技术债与后续跟踪（Code Review）

> 来源：M0（`milestone-m0-scaffold-bridge`）提交前 code review。记录在 M0 中**有意推迟**的健壮性/架构项，以及它们各自的 gating 里程碑。M0 的退出标准（可编译、可单测、数据模型就位、一次 socket 往返）不被这些项阻塞；但下列项必须在对应里程碑前清掉。
>
> 已在 M0 内即时修复（无需跟踪）：client fd 双重 close（`BridgeServer.acceptConnections` 改为由 `defer` 单点释放）；`accept()` 返回负值时对 `EINTR` `continue`、仅在其他错误 break（避免一次被中断的系统调用永久停掉 listener）。

### TD-1 · BridgeServer 阻塞 socket I/O 跑在 Swift 并发协作线程池上

- **问题**：`acceptConnections` 与每连接处理都用 `Task { }` 启动，却调用阻塞的 `Darwin.accept` / `read` / `write`。这些运行在全局协作执行器（线程数 ≈ 核心数）上：accept 循环永久占用一个协作线程，N 个并发阻塞连接再占 N 个，存在执行器饥饿/死锁风险（Swift 6 反模式）。
- **现状**：M0 测试通过（流量单条串行、核心数充足）。
- **影响里程碑**：**M3**。M3 让真实 hook 流量进入此路径，且审批往返要阻塞等待用户响应（默认 20s），届时一个阻塞 handler 占住协作线程即为饥饿场景。
- **建议方案**：accept/读写迁出协作池——改用专用 `DispatchQueue`/`Thread`，或非阻塞 socket + `DispatchSource`/kqueue。
- **涉及文件**：`VibePetCore/Bridge/BridgeServer.swift`、`VibePetCore/Bridge/BridgeSocketIO.swift`。

### TD-2 · stop() 关停依赖未定义行为，且存在 start/stop 竞态

- **问题**：(a) `stop()` 靠 `close()` 监听 fd 来唤醒阻塞在 `accept()` 的线程，但 Darwin/BSD 上此唤醒行为未定义（与 Linux 不同）；阻塞期间不重新检查 `Task.isCancelled`。(b) `state.install(...)` 在 accept Task 已启动**之后**才执行；若 `stop()` 落在该窗口，会读到 `listenFileDescriptor == -1` 提前返回，泄漏 fd。
- **现状**：概率低，M0 测试未覆盖该窗口。与 TD-1 同源——迁移到非阻塞 socket 可一并解决 (a)。
- **影响里程碑**：**M3**（随 TD-1 一并处理）。
- **建议方案**：非阻塞 accept + 可中断关停；start 时先把 fd 登记进 state 再启动 accept Task（消除竞态窗口）。
- **涉及文件**：`VibePetCore/Bridge/BridgeServer.swift`（含 `BridgeServerState`）。

### TD-3 · 支持目录权限在两个创建方之间不一致

- **问题**：`SocketPath.prepareDirectory` 把 `~/Library/Application Support/VibePet/` 强制设为 `0700`，但 `ConfigStore.write` 用默认 umask 创建同一目录。谁先跑谁定权限；若 ConfigStore 先写，存放 `bridge.sock` 的目录会停在约 `0755`，直到 `BridgeServer.start` 重新设回 `0700`。
- **影响里程碑**：**M3**（socket 实际承载流量前，目录须稳定为用户私有 0700）。
- **建议方案**：抽出统一的「确保 VibePet 支持目录存在且为 0700」工具方法，供 `SocketPath` 与 `ConfigStore` 共用。
- **涉及文件**：`VibePetCore/Bridge/SocketPath.swift`、`VibePetCore/Persistence/ConfigStore.swift`。

### TD-4 · BridgeClient 无连接/读取超时

- **问题**：`BridgeClient.send` 做阻塞 `readLine` 且无截止时间；若服务端接受连接却永不回复，客户端永久阻塞。
- **现状**：非 M0 缺口——fail-open 计时（失败 ≤2s `defer`、无响应 ≤20s `defer`）属 M3 CLI 接线。但此「阻塞读且无截止」原语正是 M3 的基础。
- **影响里程碑**：**M3**（fail-open KPI：CLI 连接失败 ≤2s 内 `defer`；M4 审批无响应 20s 倒计时后 `defer`）。
- **建议方案**：M3 接线 CLI 时为 `BridgeClient` 增加连接/读取超时（带截止时间或 `select`/`poll`），到点返回 typed error → CLI `defer`。
- **涉及文件**：`VibePetCore/Bridge/BridgeClient.swift`、`VibePetCore/Bridge/BridgeSocketIO.swift`。
