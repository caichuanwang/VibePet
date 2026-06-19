## 1. 传输层加固（TD-1~TD-4，真实流量前置）

- [x] 1.1 抽出 `VibePetCore` 内统一支持目录工具方法（确保 `~/Library/Application Support/VibePet/` 存在且为 `0700`），`SocketPath` 与 `ConfigStore` 共用（TD-3）
- [x] 1.2 `ConfigStore` 新字段验证：目录由 `ConfigStore.write` 先创建时仍为 `0700`；新增/复用单测断言（`Tests/VibePetCoreTests/`）
- [x] 1.3 `BridgeServer` 把阻塞 `accept`/`read`/`write` 迁出 Swift 并发协作池，改用专用 `DispatchQueue`/`Thread`（TD-1）
- [x] 1.4 `BridgeServer.stop()` 改为可中断关停（self-pipe/`socketpair` 唤醒 `poll`，不依赖 `close()` 唤醒未定义行为），并在 `start()` 中先登记 listen fd 再启动 accept 任务以消除 start/stop 竞态（TD-2）
- [x] 1.5 新增单测：`stop()` 在阻塞 `accept` 期间可中断、`start()` 后立即 `stop()` 不泄漏 fd（`Tests/VibePetCoreTests/`）
- [x] 1.6 `BridgeClient` 增加连接超时（非阻塞 `connect` + `poll` 截止时间，默认 ≤2s）与读取超时（`SO_RCVTIMEO`/`poll`），到点返回 typed error（`connectionTimedOut`/`readTimedOut`）（TD-4）
- [x] 1.7 新增单测：服务端接受连接但永不回复时 `BridgeClient` 在截止时间返回 typed 超时错误（`Tests/VibePetCoreTests/`）
- [x] 1.8 运行 `swift test`，回归既有 M0 socket 往返测试全绿

## 2. ClaudeCodeAdapter — Stop / Notification 解析（M3-4）

- [x] 2.1 新增 `VibePetCore/Adapters/ClaudeCodeAdapter.swift`，conform `ToolAdapter`（`tool == .claudeCode`），按 `hook_event_name` 分派
- [x] 2.2 实现 `Stop` → `.completion`：优先提取 payload summary / transcript 摘要填 `markdownSummary`，缺失时生成可读兜底文案
- [x] 2.3 实现 `Notification` → `.status`：单行 `text`
- [x] 2.4 填充 `SourceInfo`：`tool == .claudeCode`、`projectName`= cwd basename、`sessionShortId`= 会话 id 短码（有则填）
- [x] 2.5 准备本机 `Stop` / `Notification` hook fixture（`Tests/Fixtures/claude/`）
- [x] 2.6 新增 `Tests/VibePetCoreTests/ClaudeCodeAdapterParseTests.swift`：断言 Stop（有摘要/无摘要两路）与 Notification 归一化为正确 `BubbleContent` 与 `SourceInfo`；`swift test` 全绿

## 3. VibePetHooks CLI 运行时（M3-1）

- [x] 3.1 新增 `VibePetHooks/HookRuntime.swift`：从 stdin 读事件 JSON → 选 `ToolAdapter` → `parseEvent` 归一化
- [x] 3.2 通知类（`content.needsResponse == false`）走 `BridgeClient` 单向发送（写一行后返回，不读响应）→ `exit 0`
- [x] 3.3 统一 fail-open：解析失败 / `parseEvent` 返回 nil / 连接失败 / 超时 → `defer`（Claude Code：无 JSON、`exit 0`），连接/超时路径 ≤2s 返回
- [x] 3.4 `VibePetHooks/main.swift` 接入 `HookRuntime`；保持二进制小、启动快
- [x] 3.5 新增 `HookRuntime` 可测逻辑的单测（fail-open 分支、通知发送路径选择），不依赖真实 socket 的部分；`swift test` 全绿

## 4. App BridgeServerHost 路由与 PetController 状态机（M3-2）

- [x] 4.1 新增 `VibePetApp/Pet/PetController.swift`：`idle / greet / notify` 状态机（`decide` 留 M4），`completion`/`status` 事件进 `notify`、气泡收起回 `idle`，`needsResponse == true` 不进入交互态
- [x] 4.2 新增 `VibePetApp/Bridge/BridgeServerHost.swift`：App 启动运行 `BridgeServer`，收到 envelope 后 hop 到 `MainActor` 路由给 `PetController`
- [x] 4.3 `VibePetApp/main.swift` 接入 `BridgeServerHost`（启动/停止生命周期）与 `PetController`
- [x] 4.4 验证：App 运行态下经 `BridgeClient` 喂一条通知 envelope，`PetController` 进入 `notify` 并请求气泡

## 5. SpeechBubble 渲染与通用锚定（M3-3）

- [x] 5.1 新增 `VibePetCore/Geometry/BubbleAnchor.swift`：象限判定 / 尾巴落点 / 边界 clamp（距边 12pt）的**纯函数**（输入 `visibleFrame`/宠物中心/气泡尺寸 → 锚点+开向），不依赖 SwiftUI（置于 Core 以便单测，遵循 M2 `ScreenSnap` 先例）
- [x] 5.2 新增 `VibePetApp/Bubble/BubbleTheme.swift`：集中配色/圆角/字体，跟随系统明暗主题
- [x] 5.3 新增 `VibePetApp/Bubble/SpeechBubble.swift`：渲染 `.status`（单行图标+文本，6–8s 自动收起、悬停暂停）与 `.completion`（Markdown 约 6 行后内部滚动、`isError` 警示配色，8–10s 自动收起、悬停暂停）
- [x] 5.4 头部显示来源 `工具·项目名·会话短id`；宽度 240–380pt 自适应、超长内部滚动；尾巴跟踪宠物中心；VoiceOver 标签
- [x] 5.5 新增 `BubbleAnchor` 纯几何函数单测（四象限开向、边界 clamp、尾巴落点）于 `Tests/VibePetCoreTests/BubbleAnchorTests.swift`；`swift test` 全绿

## 6. 通知链路端到端联调（M3-5）

- [x] 6.1 新增 `Tests/E2E/NotificationFlowTests.swift`：headless 跑通真实 CLI 路径 stdin→`ClaudeCodeAdapter`→`HookRuntime`→`BridgeClient`→`BridgeServer`（`Stop`/`Notification` 各一例），断言归一化 envelope 送达且 `PetStateMachine` 进 `notify`；并以**子进程**方式真实运行 `VibePetHooks` 二进制（依赖加入 E2E target），断言其限时退出 `0`——覆盖 `main.swift` 进程入口的并发接线（修复了一处会挂死每次 hook 调用的 MainActor/semaphore 死锁，in-process 测试无法发现）
- [x] 6.2 新增 `Tests/VibePetAppTests/NotificationBubbleFlowTests.swift`：经 `BridgeServerHost`+`PetController`（注入 `FakePetSurface` 替身）真实路由，断言 `completion`/`status` 弹气泡、`onDismiss` 后回 `idle` 并收起气泡；启动 greet 走状态机。**注**：替身覆盖到「气泡呈现/收起生命周期」逻辑层；真实 NSWindow 像素渲染与屏上自动收起由 6.4 人工 demo 验证
- [x] 6.3 断言 App 未运行 / 连接失败时 CLI ≤2s `defer` 退出（fail-open 雏形，`Tests/E2E`）
- [x] 6.4 最终回归：`swift build` + `swift test` 全绿（97 项）
- [x] 6.5 人工 demo（已人工验证通过）：`swift run VibePetApp` → 喂 `VibePetHooks` 一条 `Stop`/`Notification` → 肉眼确认宠物头顶弹气泡并自动收起（屏上像素与窗口层级，自动化测试不覆盖）
