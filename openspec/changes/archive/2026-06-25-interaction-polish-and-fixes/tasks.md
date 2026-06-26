## 1. E — 移除决策超时（先做，解锁卡片改造）

- [x] 1.1 `PetController`：删除 `decisionTimeout`、`startDecisionTimeout(for:)`、`decisionTimeoutTask` 及其取消点；`presentFrontDecision` 不再启动超时；`requestDecision` 一直挂起直到 resolve。保留 `failOpenAllDecisions`（宠物隐藏）与 dismissal → `.defer`。
- [x] 1.2 `ApprovalCard`：移除 `timeout` 形参与 `runCountdown()`/倒计时 UI 及到零 `.defer`；保留 Allow/Deny/Always、终端降级形态、待处理计数。
- [x] 1.3 `QuestionCard`：移除 `timeout` 形参与 `runCountdown()`/倒计时 UI；dismissal 仍 `.defer`。
- [x] 1.4 同步 `PetSurface.presentApproval/presentQuestion` 协议与 `PetWindowSurface`、`BridgeServerHost` 调用点，去掉 `timeout` 传参。
- [x] 1.5 `AppConfig`：移除 `decisionTimeoutSeconds` 的存储/`with(...)`/默认值消费；`init(from:)` 用 `decodeIfPresent` 容忍旧 `config.json` 残留键（忽略不报错）。
- [x] 1.6 `SettingsView`：删除"行为"区的决策超时滑块与 `persistTimeout()`；保留开机自启与宠物选择。
- [x] 1.7 更新受影响测试（`ApprovalCardTests`、问答卡用例、`SessionStateTests`/`AppConfig` 解码、`PetController` 决策用例），删超时相关断言，新增"无倒计时、挂起至响应、dismissal→defer、旧配置含 timeout 仍解码"用例。

## 2. F — Claude 多主题提交校验修复

- [x] 2.1 `QuestionCard`：把 `hasAnySelection` 改为"全部问题已答"——`content.questions.allSatisfy { 至少一个选项且 freeform 选项非空文本 }`；`collectAnswer()` 不变。
- [x] 2.2 新增/更新用例：多问题仅答其一时提交禁用；全部答齐后启用并收集每题答案；freeform 空文本时禁用。

## 3. D — Codex PostToolUse 心跳

- [x] 3.1 `CodexAdapter`：`parseEvent`/`makeAgentEvent` 处理 `PostToolUse` → `.activityUpdated`，摘要取 `tool_name` 兜底默认串；保持 fail-open（缺 session id → nil）。
- [x] 3.2 `CodexConfigWriter.managedHookKeys` 增加 `PostToolUse`，timeout 取 `stopTimeout` 量级；`uninstall` 按 `statusMessage` 仍能精确移除该键。
- [x] 3.3 新增 fixture（`Tests/Fixtures/codex/post-tool-use.json`）与用例：`PostToolUse → activityUpdated`、`updatedAt` 推进、等待中审批不被心跳清除（reducer 守卫）、安装/卸载含 `PostToolUse` 受管键。
- [x] 3.4 onboarding/设置页提示"受管 hook 已更新，需重装一次"（文案 + 触发既有重装路径）。

## 4. C — 界面优化（统一令牌 + 状态点）

- [x] 4.1 `BubbleTheme`：在既有 dashboard 令牌基础上收敛卡片用色/圆角/字体令牌，供 `ApprovalCard`/`QuestionCard`/`SpeechBubble` 统一引用（纯实现，无 spec 变化）。
- [x] 4.2 按统一令牌重绘三类卡片（背景层/卡片层/状态色/分隔），保持现有结构与可访问性标签不变。
- [x] 4.3 宠物窗口常驻状态点：源自 `SessionState.petVisualState` 颜色映射，渲染为 `PetView`/窗口角标叠加；不改 `hitMask`、不参与指针路由。
- [x] 4.4 状态点用例/手测：running→绿、attention→橙、idle→灰；点击状态点处透明像素仍 passthrough。

## 5. 验证与收口

- [x] 5.1 `swift build` 通过；`swift test` 全绿（重点 `CodexAdapter`、`CodexConfigWriter`、`PetController`、问答卡、`AppConfig`）。
- [x] 5.2 手测：审批/问答无倒计时、挂起至点击、dismissal 回落原生；Codex 运行中会话随工具执行刷新；多主题提问答齐方可提交。
- [x] 5.3 `openspec validate interaction-polish-and-fixes --strict` 通过。
