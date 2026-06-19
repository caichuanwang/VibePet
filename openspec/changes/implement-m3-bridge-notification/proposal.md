## Why

M0 交付了 Bridge 数据模型与一次本地 socket 往返，M2 让宠物"活"在桌面，但 hook CLI 与 App 之间还没有真正打通——开发者在 Claude Code 里干的活，桌面宠物完全感知不到。里程碑 M3 打通 `VibePetHooks` ↔ App 的端到端通道，先跑通**不需回传**的通知态（`completion` / `status`）：Claude Code 跑完一轮或在等输入时，宠物头顶弹出无按钮气泡并自动收起。它对应 PRD US-4（任务状态通知），是 M4 审批闭环、M5 提问闭环得以阻塞回传的前置链路。

同时，M3 是真实 hook 流量首次进入 socket 路径的里程碑——M0 code review 中**有意推迟、明确 gate 在 M3** 的传输层健壮性债（阻塞 I/O 跑在并发协作池、关停依赖未定义行为、支持目录权限不一致、客户端无超时）必须在本里程碑清掉，否则通知链路与后续审批阻塞等待都不可靠。

## What Changes

- 新增 `VibePetHooks` CLI 运行时（`HookRuntime`）：从 stdin 读工具事件 JSON → 经选定 `ToolAdapter` 归一化为 `BridgeEnvelope` → 连 socket 发送；通知类发送后立即 `exit 0`；连接不上在 ≤2s 内 `defer` 退出（fail-open 雏形，§3.4 / §7）。二进制体积小、启动快。
- 新增 App 内 `BridgeServerHost`：App 启动运行 `BridgeServer`，收到 envelope 后路由到 `PetController`。
- 新增 `PetController` 状态机：`idle / greet / notify`（`decide` 态留 M4）按 §5.2 流转；收到 `completion` / `status` 事件进 `notify`、气泡收起后回 `idle`。
- 新增 `SpeechBubble`：渲染 `.status`（单行图标+文本，6–8s 自动收起、悬停暂停）与 `.completion`（Markdown 摘要约 6 行后内部滚动，`isError` 警示配色，8–10s 自动收起）；象限感知锚定 + 尾巴跟踪 + 边界避让 + 宽度 240–380pt（§5.3 通用）；头部显示来源 `工具·项目名·会话短id`；VoiceOver 标签。MVP 不含"回复 Agent"。
- 新增 `ClaudeCodeAdapter` 解析子集：`Stop` → `.completion`（优先提取 payload summary / transcript 摘要，缺失时生成可读兜底文案）；`Notification` → `.status`（单行）。
- **修改 `bridge-transport`**：在真实流量进入前清掉 M3-gated 传输层债——把阻塞 socket I/O 迁出 Swift 并发协作池、关停可中断且无 start/stop 竞态、统一 VibePet 支持目录 `0700` 创建、为 `BridgeClient` 增加连接/读取超时并返回 typed error 供 CLI `defer`。

## Capabilities

### New Capabilities
- `hook-cli`: `VibePetHooks` 命令行运行时——从 stdin 读取工具原生事件，经 `ToolAdapter` 归一化为 `BridgeEnvelope`，连 socket 发送；通知类立即退出，连接失败 ≤2s `defer` fail-open 退出。
- `pet-controller`: 宠物状态机 `idle / greet / notify`（`decide` 留 M4），以及 `BridgeServerHost` 把 `BridgeServer` 收到的 envelope 路由到状态机并据 `BubbleContent` 驱动气泡。
- `speech-bubble`: 由 `BubbleContent` 驱动的气泡渲染——`.status` / `.completion` 两种通知形态、自动收起与悬停暂停、象限感知锚定 + 尾巴跟踪 + 边界 clamp + 自适应宽度、来源头部与 VoiceOver。
- `claude-code-adapter`: `ClaudeCodeAdapter` 把 Claude Code 的 `Stop` 事件归一化为 `.completion`、`Notification` 事件归一化为 `.status`（M3 范围；`PreToolUse` / `AskUserQuestion` 解析与回写留 M4/M5）。

### Modified Capabilities
- `bridge-transport`: 在真实 hook 流量首次进入前加固传输层——阻塞 accept/read/write 迁出并发协作池（消除执行器饥饿）、关停可中断且消除 start/stop 竞态、支持目录统一以 `0700` 创建、`BridgeClient` 增加连接/读取超时返回 typed error。既有"路径权限 / 往返 / 残留清理 / 连接失败报错"要求保持，新增"非阻塞调度 / 可中断关停 / 超时"要求。

## Impact

- **新增源码**：`VibePetHooks/HookRuntime.swift`（复用 `BridgeClient` / `ToolAdapter`）；`VibePetApp/Bridge/BridgeServerHost.swift`；`VibePetApp/Pet/PetController.swift`；`VibePetApp/Bubble/`（`SpeechBubble.swift`、`BubbleAnchor.swift`、`BubbleTheme.swift`）；`VibePetCore/Adapters/ClaudeCodeAdapter.swift`（仅 Stop / Notification 解析部分）。
- **修改源码**：`VibePetHooks/main.swift`（接 `HookRuntime`）；`VibePetCore/Bridge/BridgeServer.swift`（+`BridgeServerState`）、`VibePetCore/Bridge/BridgeClient.swift`、`VibePetCore/Bridge/BridgeSocketIO.swift`（非阻塞调度 + 可中断关停 + 超时）；`VibePetCore/Bridge/SocketPath.swift` 与 `VibePetCore/Persistence/ConfigStore.swift`（统一 `0700` 支持目录工具方法）；`VibePetApp/main.swift`（启动 `BridgeServerHost`、接 `PetController`）。
- **新增测试**：`Tests/VibePetCoreTests/ClaudeCodeAdapterParseTests.swift`（Stop / Notification 归一化断言）；`BridgeClient` 超时返回 typed error 测试；`BridgeServer` 可中断关停 / start-stop 竞态测试；象限锚定/边界避让纯几何函数测试；`Tests/E2E/NotificationFlowTests.swift`（脚本化喂 stdin，App 运行态弹气泡 / 未运行 ≤2s defer，§8.3）。
- **复用 M0/M2**：`BridgeEnvelope` / `BubbleContent` / `BridgeResponse`、`ToolAdapter`、`BridgeServer` / `BridgeClient`、`PetView` / `PetWindowController` 几何与象限信息、`ConfigStore`（决策超时）。
- **依赖**：AppKit / SwiftUI 仅在 `VibePetApp`（`PetController` / `SpeechBubble` / `BridgeServerHost`），不进入 `VibePetCore`；`ClaudeCodeAdapter` 与传输层加固全部留在 `VibePetCore`，无第三方依赖、全程不联网。
- **运行时副作用**：App 监听 `~/Library/Application Support/VibePet/bridge.sock`；CLI 连接该 socket 发送通知；支持目录稳定为 `0700`。
- **守则**：保持 `VibePetCore` 不 import AppKit/SwiftUI；保持 fail-open——App 未运行 / socket 失败 / 输入畸形 / 超时一律让工具回退原生流程，绝不卡住 Claude Code。
- **下游解锁**：M4 在本链路上加 `decide` 态、审批气泡与阻塞回传；M3 加固后的 `BridgeClient` 超时原语正是 M4 审批无响应 20s `defer` 的基础。
