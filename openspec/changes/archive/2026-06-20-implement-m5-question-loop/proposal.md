## Why

M4 让**审批操作**（`PreToolUse` 的允许/拒绝）在桌面宠物气泡里一键决策并真实回传。里程碑 M5（PRD US-3b）让 Claude Code 的 `AskUserQuestion` **结构化多选提问**在气泡内逐题作答，经 hook 的 `updatedInput` 把答案预填回工具，使工具拿到已填输入后不再弹原生提问。

**M5-0 schema spike 结论：机制受支持（Claude Code ≥ 2.1.85）。** 官方 changelog 明确："PreToolUse hooks can now satisfy `AskUserQuestion` by returning `updatedInput` alongside `permissionDecision: "allow"`."；`AskUserQuestion` 的 `tool_input` 含 `answers`/`annotations` 等**答案输入字段**（"User answers collected by the permission component"），正是供 hook 回填用。详见 `Tests/Fixtures/claude/m5-question-spike-notes.md`。

M5 复用 M4 已就位的全部基础设施（CLI 阻塞回路、`decide` 态、`BridgeServerHost` 回传配对、`BubbleQueue`，因 `question.needsResponse == true` 与 approval 同路），只新增"提问"这一交互形态的解析、气泡与回写。

## What Changes

- **schema spike（M5-0）**：以官方 hooks 文档 + changelog + 真实 `AskUserQuestion` 输入 schema 验证 `updatedInput` 回填答案并抑制原生提问 → **支持（≥2.1.85）**。产出真实 fixture `Tests/Fixtures/claude/ask-user-question.json`（`questions[].{question, header, multiSelect, options[].{label, description}}`，取代占位）与结论笔记（含已知版本 bug 与 fail-open 兜底）。
- **解析（M5-1）**：`ClaudeCodeAdapter` 拦截 `PreToolUse(tool_name == AskUserQuestion)` → `.question`；从 `tool_input.questions` 映射 `QuestionItem` / `QuestionOption`。
- **提问气泡（M5-2）**：新增 `QuestionCard`——逐题渲染单选圈 / 复选框、选项 `label`+次行灰字 `detail`、每题恒有的"其他"（`allowsFreeform`）选中后展开文本框；提交（`⌘↩`）汇集 `QuestionAnswer`（按 `header`，单值字符串：多选以 `", "` 连接、freeform 文本顶替其 label）；倒计时到点 fail-open `defer`。
- **`decide` 态呈现提问卡（pet-controller）**：`PetController.decide` 对 `.question` 呈现 `QuestionCard`（而非 `ApprovalCard`），提交后经同一阻塞连接回传 `.question(QuestionAnswer)`，`requestId` 配对；超时 / 关闭无作答 → `.defer`。
- **`updatedInput` 预填回写（M5-3）**：`ClaudeCodeAdapter.encodeResponse(.question(answer))` 返回 `permissionDecision:"allow"` + `updatedInput`（保留原 `questions` + `answers`，answers 按 question text 归集，由 header 翻译而来）；无有效选择 / 超时 → `defer` 回退原生提问。

## Capabilities

### New Capabilities
- `question-card`: `decide` 态的结构化提问气泡——逐题渲染（单选圈 / 复选框 / 选项 `detail` / `allowsFreeform` 文本框）、提交汇集 `QuestionAnswer`（按 `header`）、倒计时到点 fail-open `defer`。

### Modified Capabilities
- `claude-code-adapter`: 新增 `PreToolUse(tool_name == AskUserQuestion)` → `.question` 解析（`QuestionItem` / `QuestionOption` 映射），与 `.question(QuestionAnswer)` → `updatedInput` 预填回写（answers 按 question text、保留 questions；无选择/超时 fail-open `defer`）。既有 `Stop` / `Notification` / `PreToolUse(approval)` 解析与审批回写要求保持。
- `pet-controller`: `decide` 态新增对 `.question` 内容的呈现——呈现 `QuestionCard` 并经同一连接回传 `.question(QuestionAnswer)`（`requestId` 配对），超时 / 无作答回 `.defer`。既有审批回传配对要求保持。

## Impact

- **新增源码**：`VibePetApp/Bubble/QuestionCard.swift`。
- **修改源码**：`VibePetCore/Adapters/ClaudeCodeAdapter.swift`（`AskUserQuestion` → `.question` 解析 + `.question` encodeResponse 的 `updatedInput` 回写）；`VibePetApp/Pet/PetController.swift`（`decide` 对 `.question` 选卡、`requestDecision` 改判 `needsResponse`）；`VibePetApp/Pet/PetWindowSurface.swift`（新增 `presentQuestion`）；`PetSurface` 协议新增 `presentQuestion`。
- **复用 M0/M4**：`QuestionContent` / `QuestionItem` / `QuestionOption` / `QuestionAnswer` / `BridgeResponse.question`（M0 已定义，仅消费）；CLI 阻塞回路与 fail-open 超时（M4 已对 `needsResponse == true` 分流，`question` 直接复用，hook-cli / 传输层 / `BridgeServerHost` 路由判定 **不改**）；`BubbleQueue` / `BubbleStackView` / `ApprovalPresentation`（多气泡堆叠与 pendingCount，提问卡同等参与）；`BubbleAnchor` / `BubbleTheme` / `BubbleShape`（锚定与主题）；`ConfigStore`（决策超时）。
- **新增/更新测试**：`Tests/VibePetCoreTests/ClaudeCodeQuestionParseTests.swift`（`AskUserQuestion` → `.question` 映射、多选、needsResponse）、`ClaudeCodeQuestionEncodeTests.swift`（`updatedInput` allow 回写 / 无选择 defer / 非 question envelope defer）；`Tests/Fixtures/claude/ask-user-question.json`（真实 schema fixture）；`Tests/VibePetAppTests/NotificationBubbleFlowTests.swift`（`decide` 呈现 `QuestionCard`、提交回传 `.question` 配对、超时 `defer`，并为 `FakePetSurface` 加 `presentQuestion`）；更新 M4 既有断言（`ClaudeCodeApprovalParseTests` 的 AskUserQuestion → `.question`、移除 `ClaudeCodeEncodeTests` 的过时 question 占位用例）。
- **依赖与守则**：AppKit/SwiftUI 仅在 `VibePetApp`（`QuestionCard` / `PetController` / `PetWindowSurface`），`ClaudeCodeAdapter` 留在 `VibePetCore`、无第三方依赖、全程不联网；fail-open 为硬要求——解析失败 / 连接失败 / 用户未响应一律让 Claude Code 回退原生提问，绝不卡住工具。
- **运行时副作用**：`AskUserQuestion` 类 hook 会阻塞 Claude Code 直至用户作答或超时（默认 20s，须 < 工具 hook timeout）。气泡作答是否真正抑制原生提问取决于运行的 Claude Code 版本——已知 #15897（多 hook 时 `updatedInput` 被忽略）、#52822（v2.1.119 回归仍弹原生），fail-open 倒计时兜底保证不卡死。
- **下游解锁**：M6 CodexAdapter 的提问降级（`requiresTerminalApproval` / 回终端）复用本里程碑确立的提问交互骨架。
