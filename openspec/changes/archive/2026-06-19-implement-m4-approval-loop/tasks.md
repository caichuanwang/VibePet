## 1. ClaudeCodeAdapter — PreToolUse → approval 解析（M4-1）

- [x] 1.1 在 `ClaudeCodeAdapter` 按 `hook_event_name == "PreToolUse"` 且 `tool_name != "AskUserQuestion"` 分派到 `.approval` 解析
- [x] 1.2 从 `tool_input` 组装 `ActionPreview`：`Bash`→`.command`、`Edit`/`Write`→`.fileChange`、`Read`→`.fileRead`、`WebFetch`→`.network`、其它→`.generic`
- [x] 1.3 填充 `ApprovalContent`（`actionPreview` + `SourceInfo` 复用 M3 逻辑）；`alwaysAllow` 暂置 `nil`（待 §3 spike 结论接入）
- [x] 1.4 准备本机 `PreToolUse` hook fixtures（Bash/Edit/Write/Read/WebFetch 各一例）于 `Tests/Fixtures/claude/`
- [x] 1.5 新增 `Tests/VibePetCoreTests/ClaudeCodeApprovalParseTests.swift`：断言五类工具归一化为正确 `ActionPreview` 变体与 `SourceInfo`；`swift test` 全绿

## 2. 风险分级启发式（M4-2，可与 §1 后并行）

- [x] 2.1 新增 `VibePetCore/Adapters/RiskClassifier.swift`：纯函数 `classify(toolName:command:) -> RiskLevel`，规则以数据（模式表）驱动
- [x] 2.2 实现危险模式 → `.high`：`rm -rf`、`sudo`、`curl … | sh`（下载管道进 shell）、`git push --force`/`-f`
- [x] 2.3 在 `ClaudeCodeAdapter` 的 approval 解析中调用 `RiskClassifier` 填 `ApprovalContent.risk`
- [x] 2.4 新增 `Tests/VibePetCoreTests/RiskClassifierTests.swift`：逐条断言危险模式 `.high`、普通命令低于 `.high`、规则数据可注入；`swift test` 全绿

## 3. Claude allowAlways schema spike（M4-3a，gate "始终允许"，先行）

- [x] 3.1 查当前 Claude Code 版本官方文档 / 抓本机 hook fixture，验证 `allowAlways` 或等价持久/会话权限规则的可落地方式
- [x] 3.2 产出最小 fixture 于 `Tests/Fixtures/claude/` 与结论记录（支持 / 不支持及原因）
- [x] 3.3 新增 `Tests/VibePetCoreTests/ClaudeCodeAllowAlwaysSpikeTests.swift`：通过时断言持久 allow 回写样例；不支持时断言 adapter 不生成 `alwaysAllow`
- [x] 3.4 据结论更新 §1.3：通过则 `alwaysAllow` 由 `tool_name` 填充，否则保持 `nil`、下游 UI 隐藏"始终允许"

## 4. ClaudeCodeAdapter — 审批决策回写（M4-3，deny/allowOnce 不依赖 §3，可先合）

- [x] 4.1 `encodeResponse`：`deny(reason:)` → `{"hookSpecificOutput":{…,"permissionDecision":"deny","permissionDecisionReason":…}}`
- [x] 4.2 `encodeResponse`：`allowOnce` → `permissionDecision:"allow"`
- [x] 4.3 `encodeResponse`：`defer` → 不输出 JSON 且 `exit 0`（fail-open 核心）
- [x] 4.4 `allowAlways(scopeHint:)` 分支：仅在 §3 spike 通过时输出持久 allow，否则不生成该分支
- [x] 4.5 新增 `Tests/VibePetCoreTests/ClaudeCodeEncodeTests.swift`：字节级断言 deny/allowOnce 输出与 defer 的"无 JSON + exit 0"语义；`swift test` 全绿

## 5. CLI 阻塞回路与 fail-open 超时（M4-4）

- [x] 5.1 `BridgeClient`：决策类用阻塞 `send`（写请求 + 阻塞读 `BridgeResponseEnvelope`，复用 M3 读取超时原语），读取截止 = 用户响应 deadline
- [x] 5.2 `HookRuntime` 按 `content.needsResponse` 分流：`false` 走 M3 单向发送；`true` 走阻塞回路
- [x] 5.3 收到响应 → `adapter.encodeResponse` → 写 stdout → `exit 0`
- [x] 5.4 分层 fail-open：连接失败/socket 损坏 ≤2s `defer`；已连接但用户未响应到 deadline（默认 20s 可配、须 < hook timeout）→ `defer`
- [x] 5.5 从 `ConfigStore` 读取决策超时（默认 20s）注入 deadline
- [x] 5.6 新增 `HookRuntime` 阻塞回路单测（分流选择、超时 `defer`、回写路径）；`swift test` 全绿

## 6. PetController.decide 态与审批气泡（M4-5）

- [x] 6.1 `PetController` 新增 `decide` 态：响应类（`needsResponse == true`）内容进入 `decide`、高亮提醒（不再被忽略）
- [x] 6.2 新增 `VibePetApp/Bubble/ApprovalCard.swift`：三段布局（来源+风险头部 / `ActionPreview` 紧凑主体 / 倒计时+按钮底部）
- [x] 6.3 按 `risk` 设配色与默认焦点：`.high` 默认焦点"拒绝"、allow 需明确点击；危险命令标红、命令超 3 行截断
- [x] 6.4 按钮：拒绝(esc)/允许一次(⌘↩)/始终允许（仅 `alwaysAllow != nil` 时显示）
- [x] 6.5 倒计时（来自 `ConfigStore` 决策超时）到点 fail-open 并显示可读提示
- [x] 6.6 新增 App 侧测试（注入替身呈现层）：断言 `.approval` 进 `decide`、按风险默认焦点、倒计时到点 `defer`；`swift test` 全绿

## 7. 回传通路与 requestId 配对（M4-6）

- [x] 7.1 `BridgeServerHost` handler 分流：`needsResponse == false` 维持 M3 回 `.defer`；`true` hop 到 `MainActor` 进 `decide`
- [x] 7.2 `PetController.requestDecision(for:) async -> BridgeResponse`：`withCheckedContinuation` + `MainActor` 单次"已完成"守卫（防双 resume）；按钮回调与倒计时共用完成入口
- [x] 7.3 handler 把决定包成 `BridgeResponseEnvelope(requestId:, response:)`（`requestId` 用请求值回填）返回，由传输层写回同连接
- [x] 7.4 映射决定：拒绝→`deny(reason:)`、允许一次→`allowOnce`、（spike 通过时）始终允许→`allowAlways(scopeHint:)`、超时/无决定→`.defer`
- [x] 7.5 新增 App 侧回传/配对测试（替身路由）：断言 deny/allowOnce/defer 回正确 `requestId`、await 不饿死其它连接；`swift test` 全绿

## 8. 队列与并发堆叠（M4-7，可与 §6/§7 并行，不阻塞 §9）

- [x] 8.1 新增 `VibePetApp/Bubble/BubbleQueue.swift`：以 `requestId` keyed 管理多请求，FIFO、最早到达者在顶层
- [x] 8.2 新增 `VibePetApp/Bubble/BubbleStackView.swift`：身后最多 2 张露细边 + 顶显"还有 N 个待处理"
- [x] 8.3 各露头卡独立倒计时、超时静默 `defer` 出栈
- [x] 8.4 优先级 `decide` > `notify` > `greet`；`decide` 在场时通知仅累计小红点（先用宠物角标）
- [x] 8.5 新增 `BubbleQueue` 逻辑单测（requestId 独立、FIFO、超时出栈、优先级）；`swift test` 全绿

## 9. 审批闭环端到端 Demo 与回归（M4-8）

- [x] 9.1 新增 `Tests/E2E/ApprovalFlowTests.swift`：headless 跑通 `PreToolUse`→`ClaudeCodeAdapter`→`HookRuntime`→阻塞回路→`BridgeServerHost`→`decide`→回传→CLI 回写；以子进程真实运行 `VibePetHooks` 二进制断言 deny/allowOnce 的 stdout 与 exit 0
- [x] 9.2 断言 fail-open 计时：App 未运行/连接失败 CLI ≤2s `defer`；已连接但用户未响应到 deadline `defer`
- [x] 9.3 `swift build` + `swift test` 全绿回归（含 M0–M3 既有用例）
- [x] 9.4 人工验收（§8.4）：安装到本机 `~/.claude/settings.json`，真实 Claude Code 会话触发需审批操作 → 气泡 ≤500ms 出现 → 点"拒绝"工具调用被真实取消、点"允许一次"放行；肉眼确认 `decide` 态高亮与倒计时
