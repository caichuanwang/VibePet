## Context

M0 建立了归一化 Bridge 模型与 socket 收发原语，但 `BridgeServer` / `BridgeClient` 只在单条串行流量、核心数充足的测试场景下验证过；M0 code review 把四项传输层健壮性债（TD-1~TD-4）明确 gate 在 M3——因为 M3 是真实 hook 流量首次进入 socket 路径的里程碑。M2 已提供宠物窗口与 `PetView`、象限/几何信息载体。

M3 的链路是单向通知：`VibePetHooks`（短命 CLI，每次 hook 触发新进程）读 stdin → `ToolAdapter` 归一化 → `BridgeClient` 连 socket 发一行 JSON；App 侧常驻 `BridgeServer` 收到后路由到 `PetController` 弹气泡。本里程碑**不做阻塞回传**（`approval` / `question` 留 M4），但必须把阻塞回传所依赖的传输层原语（可中断关停、超时）一并打好。

约束：`VibePetCore` 不得 import AppKit/SwiftUI；全程不联网；fail-open 是硬要求——任何异常都让 Claude Code 回退原生流程。

## Goals / Non-Goals

**Goals:**
- 跑通 `completion` / `status` 通知态端到端：CLI 发送 → App 弹无按钮气泡 → 自动收起。
- `ClaudeCodeAdapter` 解析 `Stop` → `.completion`、`Notification` → `.status`（仅解析，无回写）。
- `PetController` 跑通 `idle / greet / notify`；`BridgeServerHost` 把 envelope 路由上主线程。
- `SpeechBubble` 渲染两种通知形态 + 通用象限锚定/尾巴跟踪/边界避让/自适应宽度/来源头部。
- 清掉 TD-1~TD-4：阻塞 I/O 迁出协作池、关停可中断且无竞态、支持目录统一 `0700`、`BridgeClient` 连接/读取超时。
- fail-open 雏形：App 未运行/连接失败/输入畸形 → CLI ≤2s `defer`。

**Non-Goals:**
- `approval` / `question` 解析、审批气泡、`decide` 态、阻塞回传与 `requestId` 配对（M4/M5）。
- `PreToolUse` / `AskUserQuestion` 解析、风险分级、`allowAlways` / `updatedInput` spike（M4/M5）。
- 多气泡队列堆叠（M4-7）、CodexAdapter（M6）、安装器（M6）。
- `allowAlways` / `updatedInput` 等 schema spike——本里程碑不触碰需回传路径。

## Decisions

### D1 · 通知发送走单向 fire-and-forget，不复用阻塞 `send`
现有 `BridgeClient.send` 写完请求后**阻塞读** `BridgeResponseEnvelope`，是为审批回传设计的。通知类不需要回传，CLI 写完即退出。
- **决策**：给 `BridgeClient` 增一个单向发送方法（写一行 JSON 后返回，不读响应）；`HookRuntime` 对 `content.needsResponse == false` 的 envelope 走该路径。`BridgeServer` 端对 `needsResponse == false` 的 envelope 处理后不回写（或回写失败被既有 `catch` 静默吞掉，因客户端已关闭）。
- **替代**：让 CLI 仍调阻塞 `send`、靠读超时返回——会引入无谓的 20s/超时等待与误报，且与"立即 exit 0"语义冲突。否决。

### D2 · 阻塞 socket I/O 迁出 Swift 并发协作池（TD-1）
`accept` / `read` / `write` 是阻塞系统调用，当前跑在 `Task {}`（全局协作执行器）上，accept 循环永久占用一个协作线程。
- **决策**：`BridgeServer` 的 accept 循环与每连接读写迁到专用 `DispatchQueue`（`.userInitiated`，串行 accept + 并发处理子队列）或专用 `Thread`，不再用 `Task {}` 承载阻塞调用。处理完一条 envelope 后再 hop 回 `MainActor` 交给 `PetController`。
- **替代**：非阻塞 socket + `DispatchSource.read`/kqueue——更"正确"但代码量与复杂度高，M3 通知态流量低，专用队列足够；保留为后续可演进方向。

### D3 · 可中断关停用 self-pipe 唤醒，fd 先登记再启动 accept（TD-2）
Darwin 上 `close()` 唤醒阻塞 `accept` 是未定义行为；且 `state.install` 在 accept 启动之后才执行，存在 start/stop 竞态窗口。
- **决策**：(a) 用 self-pipe / `socketpair` 唤醒——`accept` 改为 `poll`/`select` 同时监听 listen fd 与唤醒 fd，`stop()` 向唤醒端写一字节使 `poll` 返回、循环检查停止标志后退出；(b) `start()` 先把 listen fd 登记进 `BridgeServerState` 再启动 accept 任务，消除竞态窗口。
- **替代**：仅设 `SO_RCVTIMEO` 让 accept 周期性超时轮询 `isCancelled`——可行但引入轮询延迟与空转；self-pipe 是立即、确定的唤醒。

### D4 · `BridgeClient` 连接/读取超时（TD-4）
`connect` 与 `readLine` 均无截止时间。
- **决策**：连接用非阻塞 `connect` + `poll` 截止时间；读取用 `setsockopt(SO_RCVTIMEO)`（或 `poll` 截止）。到点返回 typed error（`connectionTimedOut` / `readTimedOut`）。连接超时默认短（≤2s，对应 fail-open KPI）；读取超时本里程碑通知态用不到回传，但原语就位供 M4 的 20s 决策倒计时复用。
- **替代**：dispatch 上包 `Task` + `withTimeout`——无法真正中断底层阻塞 `read`，线程仍被占。否决。

### D5 · 支持目录 0700 统一工具方法（TD-3）
`SocketPath.prepareDirectory` 强制 `0700`，但 `ConfigStore.write` 用默认 umask 建同一目录，谁先跑谁定权限。
- **决策**：抽出 `VibePetCore` 内单一工具方法（如 `SupportDirectory.ensure()`），保证目录存在且为 `0700`；`SocketPath` 与 `ConfigStore` 共用。

### D6 · `PetController` 在 MainActor，几何逻辑做成可测纯函数
`PetController` / `SpeechBubble` 在 `VibePetApp`（可用 AppKit/SwiftUI）。`BridgeServerHost` 把 server 的 `@Sendable` handler 适配为 `await MainActor.run` 投递给 `PetController`。
- **决策**：象限判定、尾巴落点、边界 clamp 等几何算法抽到 `BubbleAnchor` 的**纯函数**（输入 `visibleFrame` / 宠物中心 / 气泡尺寸 → 输出锚点与开向），不依赖 SwiftUI，便于单测；`SpeechBubble` 仅消费其结果。`BubbleTheme` 集中配色/圆角/字体（M6 再做主题化打磨，这里只占位集中点）。

### D7 · `ClaudeCodeAdapter` 仅解析 Stop / Notification 子集
- **决策**：按 `hook_event_name`（或等价字段）分派；`Stop` → `.completion`，优先取 payload 中 summary / transcript 摘要，缺失则生成可读兜底；`Notification` → `.status` 单行。`PreToolUse` / `AskUserQuestion` 分支与 `encodeResponse` 留 M4/M5（本里程碑 `encodeResponse` 可对通知类返回空/不适用）。来源 `SourceInfo` 从 cwd basename 与 session id 短码填充。

### D8 · `HookRuntime` 统一 fail-open
- **决策**：`HookRuntime` 捕获所有异常（解析失败、`parseEvent` 抛错/返回 nil、连接失败、超时）→ 统一映射为 `defer` 结果（Claude Code：无 JSON、`exit 0`），并确保连接/超时路径在 ≤2s 内返回。

## Risks / Trade-offs

- **[`Stop` 事件 payload 摘要字段形状未知]** → 用当前 Claude Code 版本本机 hook fixture 固化样例；解析以"有摘要取摘要、无摘要走兜底"双分支实现，单测覆盖两路，避免对字段强假设。
- **[迁出协作池 + self-pipe 引入手写并发原语]** → 用 `BridgeServerState` 集中持有 fd / 唤醒 fd / 停止标志并加锁；新增"可中断关停 / start-stop 竞态"单测专门压这条路径。
- **[通知态服务端仍按 handler 返回响应]** → D1 让服务端对 `needsResponse == false` 不回写、客户端不读；即便回写也因连接已关被既有 `catch` 吞掉，不影响 fail-open。
- **[`PetView` 几何与气泡锚定耦合 AppKit 坐标系]** → 锚定算法抽为纯函数、以值类型（`CGRect`/`CGPoint`，非 SwiftUI 专有类型）跨界，保持 Core 无 UI 依赖且可测。
- **[读取超时本里程碑无消费者]** → 仅落地原语 + 单测，不接入通知路径，避免为 M4 过度设计的同时保证 M4 可直接复用。

## Migration Plan

纯增量、无数据迁移：新增源码与对 `bridge-transport` 的内部加固，既有 `config.json` / socket 行为向后兼容。验证顺序：先 `bridge-transport` 加固（含新单测）→ `ClaudeCodeAdapter` 解析（单测）→ `HookRuntime` / CLI → `BridgeServerHost` / `PetController` → `SpeechBubble` → E2E 联调脚本。每步 `swift test` 必须全绿；传输层改动后回归既有 M0 往返测试。回滚：各文件独立提交，必要时单独 revert 而不影响 M0/M2。

## Open Questions

- `Stop` 事件实际携带哪个摘要字段（`transcript` / `summary` / 其它）？以本机 fixture 为准固化，决定兜底文案触发条件。
- self-pipe 唤醒 vs `SO_RCVTIMEO` 轮询的最终取舍——实现时按 `BridgeSocketIO` 现有封装就近选更简者，二者均满足"可中断关停"要求。
