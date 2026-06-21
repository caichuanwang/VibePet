## 1. AskUserQuestion updatedInput schema spike（M5-0）

- [x] 1.1 查当前 Claude Code 官方 hooks 文档 + changelog（v2.1.85）确认 `PreToolUse` 可经 `updatedInput` + `permissionDecision:"allow"` 满足 `AskUserQuestion`
- [x] 1.2 确认 `AskUserQuestion` 真实 `tool_input` schema（`questions[].{question, header, multiSelect, options[].{label, description}}`）及答案输入字段 `answers`/`annotations`（按 question text 归集）
- [x] 1.3 结论：机制**支持**（≥2.1.85）；记录已知 bug（#15897 多 hook 忽略 updatedInput、#52822 v2.1.119 仍弹原生）与 fail-open 兜底
- [x] 1.4 产出真实 fixture `Tests/Fixtures/claude/ask-user-question.json`（取代占位 `pretooluse-askuserquestion.json`）
- [x] 1.5 产出结论笔记 `Tests/Fixtures/claude/m5-question-spike-notes.md`（支持结论、schema、已知 bug、复评点）

## 2. ClaudeCodeAdapter — AskUserQuestion → question 解析（M5-1）

- [x] 2.1 `parseEvent` 对 `PreToolUse` 且 `tool_name == "AskUserQuestion"` 分派到 `makeQuestionEnvelope`
- [x] 2.2 从 `tool_input.questions` 映射 `QuestionItem`（`prompt`/`header` 含兜底/`multiSelect`）与 `QuestionOption`（`label`/`detail`/`allowsFreeform=false`）；每题追加合成"其他"（`allowsFreeform=true`）；空/无效 → nil（fail-open）
- [x] 2.3 新增 `Tests/VibePetCoreTests/ClaudeCodeQuestionParseTests.swift`：断言单选/多选/带 detail/无 header 兜底归一化为 `.question` 且 `needsResponse == true`；更新 `ClaudeCodeApprovalParseTests` 的 AskUserQuestion 断言；`swift test` 全绿

## 3. 提问气泡 QuestionCard + decide 呈现（M5-2）

- [x] 3.1 新增 `VibePetApp/Bubble/QuestionCard.swift`：逐题渲染 `title`/`prompt`/`options`，选项 `label`+次行灰字 `detail`
- [x] 3.2 单选用单选圈互斥、多选用复选框；每题恒有的"其他"（`allowsFreeform`）选中后展开文本框
- [x] 3.3 提交（`⌘↩`）汇集 `QuestionAnswer`：`answers[header]` 单值字符串 = 单选 label / 多选 `", "` 连接 / freeform 文本顶替 label；无作答（或"其他"无文本）则禁用
- [x] 3.4 倒计时（来自决策超时）到点或关闭无作答 → 完成回调 `.defer`（fail-open）；复用 `BubbleStackView`/`ApprovalPresentation` 堆叠
- [x] 3.5 `PetController`：`requestDecision` 改判 `needsResponse`；`presentFrontDecision` 按 content 选 `presentApproval`/`presentQuestion`；`PetSurface` 新增 `presentQuestion`，production `PetWindowSurface` 实现（re-measure 锚定 + 交互 key 窗）
- [x] 3.6 新增 App 侧测试（`FakePetSurface.presentQuestion`）：断言 `.question` 进 `decide` 并呈现 `QuestionCard`、提交回 `.question(QuestionAnswer)` 配对、超时回 `.defer`；`swift test` 全绿

## 4. updatedInput 预填回写（M5-3）

- [x] 4.1 `encodeResponse(.question(answer))`：输出 `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{questions,answers}}}`，`answers` 按 question text（由 header 翻译）、保留 `questions`
- [x] 4.2 无有效选择 / 非 question envelope / `defer` → 无 JSON + `exit 0`（fail-open）
- [x] 4.3 新增 `Tests/VibePetCoreTests/ClaudeCodeQuestionEncodeTests.swift`：字节级断言 single-select allow+updatedInput、multi-select 串、无选择 defer、非 question envelope defer；移除 `ClaudeCodeEncodeTests` 过时 question 占位用例；`swift test` 全绿
- [x] 4.4 新增 `Tests/E2E/QuestionFlowTests.swift`：真实 CLI 路径（stdin→adapter→HookRuntime 阻塞回路→server 回 `.question`→encodeResponse→stdout）断言 `allow`+`updatedInput`、defer 无 stdout、App 未运行 ≤2s fail-open，并以子进程真实运行 `VibePetHooks` 二进制断言 stdout
- [x] 4.5 `swift build` + `swift test` 全绿回归（含 M0–M4 既有用例）
