## Why

M3 打通了 hook CLI ↔ App 的**单向通知**链路（`completion` / `status` 弹无按钮气泡），但 MVP 的核心价值还没到位：开发者在 Claude Code 里触发的**决策操作**（`PreToolUse`，如 `Bash` / `Edit` / `Write` / `Read` / `WebFetch`）目前仍只能回终端原生确认。里程碑 M4 让这些决策操作在桌面宠物的审批气泡里**一键允许/拒绝并真实回传**——这是 PRD US-3 的核心闭环，也是端到端闭环 KPI、≤500ms 延迟 KPI、Fail-open 100% KPI 的验收点。

M4 是 hook 路径上**第一次需要阻塞回传**的里程碑：CLI 发送决策事件后须保持连接等待用户响应，App 在 `decide` 态弹审批气泡、用户点按后经同一连接回传 `BridgeResponseEnvelope`（`requestId` 配对），CLI 据此回写 stdout 让工具真实放行或取消。M3 已把传输层原语（异步 handler 回写、连接/读取超时、可中断关停）打好，本里程碑在其上接交互与回写，不改传输层。

## What Changes

- **解析（M4-1）**：`ClaudeCodeAdapter` 新增 `PreToolUse`（`tool_name` ≠ `AskUserQuestion`）→ `.approval`；从 `tool_input` 组装 `ActionPreview`：`Bash`→`.command`、`Edit`/`Write`→`.fileChange`、`Read`→`.fileRead`、`WebFetch`→`.network`、其它→`.generic`；`alwaysAllow` 用 `tool_name` 填充（仅当 M4-3a spike 通过）。
- **风险分级（M4-2）**：新增 `RiskClassifier`，按工具名 + 命令模式判定 `RiskLevel`；危险模式（`rm -rf`、`sudo`、`curl … | sh`、`git push --force` 等）→ `.high`；规则可配置、可单测。
- **回写（M4-3 / M4-3a）**：`ClaudeCodeAdapter.encodeResponse` 把 `deny` → `permissionDecision:"deny"` + reason、`allowOnce` → `permissionDecision:"allow"`、`defer` → 不输出 JSON 且 `exit 0`；`allowAlways` 仅在 M4-3a schema spike 验证可落地时启用，否则 adapter 不生成 `alwaysAllow`、UI 隐藏"始终允许"。
- **CLI 阻塞回路（M4-4）**：`VibePetHooks` 对决策类事件（`needsResponse == true`）发送后保持连接等待 `BridgeResponseEnvelope`（默认 20s 可配、且小于工具 hook timeout）；收到→按 adapter 回写 stdout→`exit 0`；App 未运行/连接失败/socket 损坏→`defer` 且 ≤2s 退出；已连接但用户未响应→到点 `defer`。
- **`decide` 态与审批气泡（M4-5）**：`PetController` 新增 `decide` 态（高亮提醒）；新增 `ApprovalCard` 三段布局（头部来源+风险 / 主体 `ActionPreview` 紧凑渲染 / 底部倒计时+按钮），按 `risk` 设配色与默认焦点（`.high` 默认焦点"拒绝"），按钮 拒绝(esc)/允许一次(⌘↩)/始终允许(仅 `alwaysAllow≠nil`)，危险命令标红、超 3 行截断，倒计时到点 fail-open。
- **回传通路与 `requestId` 配对（M4-6）**：`BridgeServerHost` 对 `needsResponse == true` 的 envelope 不再立即回 `.defer`，而是路由到 `PetController.decide` 并 **await** 用户决定，经同一阻塞连接回传 `BridgeResponseEnvelope`（`requestId` 配对）；超时回 `.defer`。
- **队列与并发堆叠（M4-7）**：多个需回传气泡以 `requestId` 独立；卡牌堆叠+露头（身后最多 2 张露细边，顶显"还有 N 个待处理"）；FIFO 最早到达者在顶层；露头卡各自倒计时、超时静默 `defer` 出栈；优先级 `decide` > `notify` > `greet`，`decide` 在场时通知仅累计小红点。
- **端到端 Demo（M4-8）**：真实 Claude Code 会话触发需审批操作 → 气泡 ≤500ms 出现 → "拒绝"真实取消、"允许一次"真实放行；fail-open 路径达标。

## Capabilities

### New Capabilities
- `risk-classifier`: 按工具名 + 命令模式把审批动作归一为 `RiskLevel`（含危险模式启发式），规则可配置、可单测，供审批气泡配色与默认焦点使用。
- `approval-card`: `decide` 态的审批气泡——三段布局（来源+风险头部 / `ActionPreview` 紧凑主体 / 倒计时+按钮底部）、按风险配色与默认焦点、按钮集（拒绝/允许一次/始终允许）、危险命令标红与截断、倒计时到点 fail-open。
- `bubble-queue`: 多个需回传气泡的队列与并发堆叠——`requestId` 独立、FIFO 顺序、卡牌露头与"还有 N 个待处理"、各自倒计时与超时出栈、`decide`/`notify`/`greet` 优先级。

### Modified Capabilities
- `claude-code-adapter`: 新增 `PreToolUse` → `.approval` 解析（`ActionPreview` 组装 + `alwaysAllow` 填充）与审批决策回写（`deny`/`allowOnce`/`defer` 的 stdout JSON 与 exit 语义；`allowAlways` 受 M4-3a spike gate）。既有 `Stop`/`Notification` 解析要求保持。
- `hook-cli`: 新增决策类事件的**阻塞回路**——发送后保持连接等待 `BridgeResponseEnvelope`（默认 20s 可配），收到按 adapter 回写 stdout、`exit 0`；连接失败 ≤2s `defer`、用户未响应到点 `defer`。既有"通知不等待 / fail-open"要求保持。
- `pet-controller`: 新增 `decide` 态（响应类内容进入交互态而非被忽略）与 `BridgeServerHost` 回传——对 `needsResponse == true` 的 envelope await 用户决定后经同一连接回传 `BridgeResponseEnvelope` 并以 `requestId` 配对，超时回 `.defer`。既有 `idle`/`greet`/`notify` 与路由要求保持。

## Impact

- **新增源码**：`VibePetCore/Adapters/RiskClassifier.swift`；`VibePetApp/Bubble/ApprovalCard.swift`、`VibePetApp/Bubble/BubbleQueue.swift`、`VibePetApp/Bubble/BubbleStackView.swift`。
- **修改源码**：`VibePetCore/Adapters/ClaudeCodeAdapter.swift`（`PreToolUse` 解析 + `encodeResponse` 审批回写）；`VibePetHooks/HookRuntime.swift` 与 `VibePetCore/Bridge/BridgeClient.swift`（决策类阻塞等待回传 + 超时，复用 M3 的读取超时原语）；`VibePetApp/Pet/PetController.swift`（`decide` 态）、`VibePetApp/Bridge/BridgeServerHost.swift`（await 用户决定后回传，不再恒回 `.defer`）。
- **复用 M0/M3**：`ApprovalContent` / `ActionPreview` / `RiskLevel` / `AlwaysAllowOption` / `BridgeResponseEnvelope` / `ApprovalDecision`（M0 `bridge-protocol` 已定义，M4 仅消费，不改协议）；`BridgeServer.Handler`（已是 `async throws -> BridgeResponseEnvelope`，写回同连接 + 超时已就位，**传输层不改**）；`SpeechBubble`/`BubbleAnchor`/`BubbleTheme`（气泡锚定与主题）；`ConfigStore`（决策超时配置）。
- **新增测试**：`Tests/VibePetCoreTests/ClaudeCodeApprovalParseTests.swift`（Bash/Edit/Write/Read/WebFetch → `ActionPreview`）、`RiskClassifierTests.swift`（危险模式分级）、`ClaudeCodeEncodeTests.swift`（deny/allowOnce/defer 回写字节与 exit 语义）、`ClaudeCodeAllowAlwaysSpikeTests.swift`（M4-3a fixture）；`Tests/Fixtures/claude/`（PreToolUse 样例）；`Tests/E2E/ApprovalFlowTests.swift`（阻塞回路 + fail-open 计时）；App 侧 `decide` 路由/回传/配对替身测试。
- **依赖与守则**：AppKit/SwiftUI 仅在 `VibePetApp`（`ApprovalCard`/`BubbleQueue`/`PetController`/`BridgeServerHost`），`ClaudeCodeAdapter`/`RiskClassifier` 留在 `VibePetCore`、无第三方依赖、全程不联网；fail-open 为硬要求——解析失败/连接失败/超时一律让 Claude Code 回退原生确认，绝不卡住工具。
- **运行时副作用**：决策类 hook 会阻塞 Claude Code 直至用户响应或超时（默认 20s，须 < 工具 hook timeout）；"始终允许"是否可用取决于 M4-3a spike 结论。
- **下游解锁**：M5 提问闭环（`AskUserQuestion` → `.question` + `updatedInput` 回写）复用本里程碑的阻塞回路、`decide` 态与回传配对；M6 CodexAdapter 复用 `ActionPreview` 组装与审批回写骨架。
