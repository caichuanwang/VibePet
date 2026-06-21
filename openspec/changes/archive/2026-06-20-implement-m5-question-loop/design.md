## Context

M0 定义了归一化协议（含 `QuestionContent` / `QuestionItem` / `QuestionOption` / `QuestionAnswer` / `BridgeResponse.question`）。M3 打通通知态。M4 打通审批阻塞回路（CLI 阻塞回路、`decide` 态、`PetController.requestDecision(for:) async -> BridgeResponse`、`BridgeServerHost` 回传配对、`BubbleQueue`）。

关键现状：**`question` 与 `approval` 同为 `needsResponse == true`**。CLI 对 `needsResponse == true` 的阻塞分流（M4-4）、`BridgeServerHost` 对 `needsResponse == true` 路由进 `decide` 并 await（M4-6）、`requestDecision` 返回的 `BridgeResponse` 可承载 `.question(QuestionAnswer)` —— 对 `.question` 已天然适用。M5 不改传输层、不改 hook-cli、不改 `BridgeServerHost` 的路由判定。

约束：`VibePetCore` 不得 import AppKit/SwiftUI；全程不联网；**fail-open 是硬要求**——解析失败 / 连接失败 / 用户未响应一律让 Claude Code 回退原生提问。

## Spike Outcome (M5-0) — 决定本里程碑形态

**问题**：`PreToolUse` hook 能否回填 `AskUserQuestion` 答案并抑制原生提问？

**结论：支持（Claude Code ≥ 2.1.85）。** 官方 changelog："PreToolUse hooks can now satisfy `AskUserQuestion` by returning `updatedInput` alongside `permissionDecision: "allow"`."；`AskUserQuestion` 的 `tool_input` 含 `answers`/`annotations` 答案输入字段（"collected by the permission component"），`updatedInput` 可填之。早先 spike 误判为"不支持"，根因是依据被截断的文档 + "答案是输出"的错误演绎，且未查 `AskUserQuestion` 实际输入 schema——已纠正。详见 `Tests/Fixtures/claude/m5-question-spike-notes.md`。

**已知版本 bug（需防御）**：#15897（多 PreToolUse hook 时 `updatedInput` 被忽略）、#52822（v2.1.119 回归：hook 跑了但交互模式仍弹原生）。靠 fail-open 倒计时兜底——非抑制版本最终走 `defer` → 原生提问，绝不卡死。

## Goals / Non-Goals

**Goals:**
- `ClaudeCodeAdapter` 解析 `AskUserQuestion` → `.question`；`encodeResponse(.question)` → `allow` + `updatedInput`。
- `QuestionCard`：逐题单选/多选/选项 detail/freeform，提交汇集 `QuestionAnswer`，倒计时 fail-open。
- `PetController.decide` 对 `.question` 呈现 `QuestionCard`，回传 `.question(QuestionAnswer)`，`requestId` 配对。
- 复用 M4 阻塞回路/队列，不改传输层与 hook-cli。

**Non-Goals:**
- 改动 `bridge-protocol` / `bridge-transport` / hook-cli / `BridgeServerHost` 路由判定。
- 改动审批解析/回写、`ApprovalCard`、`RiskClassifier`。
- CodexAdapter 提问降级（M6）。
- 写用户 `settings.json` 持久权限（与提问无关）。

## Decisions

### D1 · spike 先行，结论"支持" → 走完整路径
- **决策**：以官方文档 + changelog + 真实 schema 验证（结论：支持 ≥2.1.85），实现完整 `.question` 解析 + `updatedInput` 回写；记录已知 bug，用 fail-open 兜底而非据此降级。
- **替代**：沿用早先错误的"不支持"降级——会错误砍掉 M5 主用户故事且测试反向锁死。否决（本次即纠正该错误）。

### D2 · 复用 M4 阻塞回路与 `decide` 回传，传输层/hook-cli/路由判定全不改
- **决策**：`question` 与 `approval` 同为 `needsResponse == true`，CLI 分流（M4-4）与 `BridgeServerHost` 路由（M4-6）已覆盖；`requestDecision` 返回类型已能承载 `.question`。M5 只在 `decide` 呈现层按 `content` case 选卡。
- **替代**：为 question 新开回传通道——重复造层。否决。

### D3 · `PetController.requestDecision` 改判 `needsResponse`，按 content 选卡
- **决策**：`requestDecision` 由"仅 `.approval`"改为"任何 `needsResponse == true`"入队；`presentFrontDecision` 按 `front.envelope.content` 分派 `surface.presentApproval` / `surface.presentQuestion`，二者共用同一 `onDecision`（resolveDecision）与超时/队列/单次完成守卫。`PendingDecision` 不再缓存 `approval`，呈现时解包。
- **替代**：为 question 复制一套队列/超时——与审批逻辑重复。否决。

### D4 · `QuestionCard` 与 `ApprovalCard` 平级，复用 `BubbleStackView` / `ApprovalPresentation`
- **决策**：`QuestionCard` 是 `VibePetApp/Bubble` 下与 `ApprovalCard` 平级的视图，输入 `QuestionContent` + 决策超时 + `ApprovalPresentation`（仅 pendingCount），输出完成回调（`.question(QuestionAnswer)` 或 `.defer`）。复用 `BubbleStackView` 堆叠、`SpeechBubble`/`BubbleAnchor`/`BubbleTheme`/`BubbleShape` 锚定与主题。production `PetWindowSurface` 像 presentApproval 一样 re-measure 卡片尺寸再锚定。
- **替代**：把提问塞进 `ApprovalCard` 加分支——布局差异大、难测难维护。否决。

### D5 · 答案汇集对齐 `QuestionAnswer`：按 header，多选 `", "` 连接、freeform 内联进值；encode 翻译为 question text
- **决策**：`QuestionCard` 按 `QuestionItem.header` 归集为**单个字符串值**：单选 → 选中 label；多选 → 选中 label 以 `", "` 连接；freeform（"其他"）→ 用输入文本顶替其 label。`encodeResponse` 只见归一化 envelope（无原始 stdin），故从 `QuestionContent` 重建 `updatedInput.questions`（**排除合成的"其他"选项**），并把 header-keyed 答案翻译为 question-text-keyed `answers`（`updatedInput` 整体替换输入，必须保留 questions）。
- **依据**：官方 Agent SDK user-input 文档明确多选"pass an array of labels **or** join them with `", "`"、freeform "Other" 的"custom text as the answer value"（**无 annotations 输出**);同源开源实现 Open Island 亦用 `", "` 连接 + 每题追加 "Other"(`allowsFreeform`)、文本内联进答案值。早先"多选用 JSON 数组串、freeform 走 annotations"的写法不符合契约,已纠正。
- **替代**：把原始 `tool_input` 透传进 envelope/encode——污染协议边界。否决（重建自归一化内容即可,且可单测）。`QuestionAnswer.freeform` 独立字段在此模型下冗余,已移除。

### D6 · 全程 fail-open，吸收版本 bug
- **决策**：无有效选择 / 超时 / 关闭 → `encodeResponse` 与卡片完成回调均 `defer`（无 JSON、exit 0）。App 倒计时 + CLI 读取截止双层兜底；即便运行的 Claude Code 版本不抑制原生提问（#52822），最终也回退原生，不卡死。
- **替代**：假定 `updatedInput` 必定抑制——遇回归版本会双重提问/卡住。否决。

## Risks / Trade-offs

- **[运行版本不抑制原生提问 / 多 hook 忽略 updatedInput]（#52822 / #15897）** → fail-open 倒计时兜底；spike 笔记记录版本要求（≥2.1.85）与复评点。
- **[多选 / freeform 的 `updatedInput` 值格式]** → 已据官方 SDK user-input 文档 + Open Island 实现确定：多选 `", "` 连接、freeform 文本作为答案值（无 annotations）；端到端值仍待一次 live session 最终复核（同写回路其余部分）。`ClaudeCodeQuestionEncodeTests` 字节级断言 single/multi-select 与"其他"被剔除。
- **[answers 键 header vs question text 错配]** → encode 通过请求 envelope 的 `QuestionItem` 做 header→prompt 翻译，单测断言 `answers["<question text>"]`。
- **[continuation 双 resume / 泄漏]** → 复用 M4 `MainActor` 单次"已完成"守卫；提交与倒计时共用完成入口。
- **[早先错误结论遗留]** → 同步纠正技术方案 §4.1 / PRD US-3b 脚注与 spike 笔记，移除反向锁死的测试。

## Migration Plan

纯新增 + 行为扩展，无数据/配置迁移。顺序：M5-0（spike 支持结论）→ M5-1（解析）→ M5-2（`QuestionCard` + pet-controller 呈现）→ M5-3（`updatedInput` 回写）。回滚：改动局限在 `AskUserQuestion` 解析/回写、`QuestionCard` 与 `decide` 选卡分支；回退即 `AskUserQuestion` 不再进 `decide`，审批与通知链路不受影响。

## Open Questions

- 多选 `", "` 连接值与 freeform "Other" 答案值的端到端表现——以一次真实 Claude Code 会话最终复核（格式已据官方 SDK 文档 + Open Island 确定）。
- 各工具 hook timeout 与默认 20s 决策窗口的安全间距——以本机实测为准、可配（沿用 M4 结论）。
