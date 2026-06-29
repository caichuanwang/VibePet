# Hook 事件、权限与宠物状态盘点

本文记录当前 VibePet 对 Claude Code 与 Codex hook 的安装入口、事件归一化、权限交互、特殊问题流和宠物状态映射。它是基于当前代码的行为快照，主要对应：

- `VibePetCore/Install/ClaudeCodeConfigWriter.swift`
- `VibePetCore/Install/CodexConfigWriter.swift`
- `VibePetCore/Adapters/ClaudeCodeAdapter.swift`
- `VibePetCore/Adapters/CodexAdapter.swift`
- `VibePetCore/Session/SessionState.swift`
- `VibePetApp/Pet/PetController.swift`
- `VibePetApp/Bubble/ApprovalCard.swift`
- `VibePetApp/Bubble/QuestionCard.swift`

## 总览

VibePet 当前一共管理 16 个 hook 入口：

| 工具 | 管理的 hook 数量 | 配置位置 |
|---|---:|---|
| Claude Code | 12 | `~/.claude/settings.json` 的 `hooks` |
| Codex | 4 | `~/.codex/hooks.json`，并开启 `~/.codex/config.toml` 的 `[features].hooks` |

但真正会阻塞用户、要求用户点击或提交的入口只有两类：

| 工具 | 阻塞入口 | 展示 |
|---|---|---|
| Claude Code | `PermissionRequest` | 普通工具展示审批卡；`AskUserQuestion` 展示问题卡 |
| Codex | `PermissionRequest` | 普通权限展示审批卡；自由输入类请求降级为终端处理 |

其他 hook 都是 fire-and-forget 通知：更新会话状态、显示状态/完成气泡，或者只刷新 running 时间，不要求用户做权限决策。

## Claude Code Hook

Claude Code 安装 12 个 hook key。安装器为每个 key 写入一个 VibePet managed matcher group；只有 `PermissionRequest` 写入长 timeout，因为它可能等待用户决策。

| Hook | 触发时机 | VibePet 事件 | Bubble 展示 | 权限关系 | 宠物状态 |
|---|---|---|---|---|---|
| `SessionStart` | Claude 会话开始 | `sessionStarted` | `status` | 无 | 会话 running；新会话触发 greeting/waving |
| `UserPromptSubmit` | 用户提交 prompt | `activityUpdated` | `status` | 无 | running |
| `PreToolUse` | 工具执行前 | `activityUpdated` | `status` | 无 | running；不覆盖正在等待的权限/问题 |
| `PermissionRequest` | Claude 请求权限 | 普通工具：`permissionRequested` | `approval` | 用户允许/拒绝/defer 后回传 Claude | waiting/decide |
| `PermissionRequest` + `AskUserQuestion` | Claude 结构化提问 | `questionAsked` | `question` | 用户提交答案后回写 `updatedInput`；否则 defer | waiting/decide |
| `PostToolUse` | 工具执行后 | 忽略 | 无 | 无 | 不变 |
| `Stop` | 一轮任务结束 | `sessionCompleted` | `completion` | 无 | completed；通常回到 idle |
| `Notification` | Claude 通知 | `activityUpdated` | `status` | 无 | notify bubble；宠物本体 idle |
| `SubagentStart` | 子代理开始 | `activityUpdated` | `status` | 无 | running |
| `SubagentStop` | 子代理结束 | `activityUpdated` | `status` | 无 | running |
| `SessionEnd` | 会话结束 | `sessionCompleted(isSessionEnd: true)` | `completion` | 无 | completed |
| `StopFailure` | 停止失败/错误完成 | `sessionCompleted(isError: true)` | `completion` | 无 | failed |
| `PermissionDenied` | Claude 权限被拒绝 | `actionableStateResolved` | `status` | 清除等待态 | running |
| `PreCompact` | 上下文压缩前 | `activityUpdated` | `status` | 无 | running |

### Claude 审批卡

`PermissionRequest` 且 `tool_name != "AskUserQuestion"` 时展示审批卡。

| Claude tool | VibePet 预览 | 标题 |
|---|---|---|
| `Bash` | command | `运行命令` |
| `Edit` | fileChange | `修改文件` |
| `Write` | fileChange | `修改文件` |
| `Read` | fileRead | `读取文件` |
| `WebFetch` | network | `访问网络` |
| 其他 | generic | `请求执行 <toolName>` |

按钮行为：

| 用户操作 | VibePet response | 写回 Claude 的 hook output |
|---|---|---|
| `允许一次` | `.approval(.allowOnce)` | `decision.behavior: "allow"` |
| `拒绝` | `.approval(.deny(reason: nil))` | `decision.behavior: "deny"` |
| 关闭/无法展示/defer | `.defer` | 空 stdout，退出 0，让 Claude 回到原生流程 |

当前不展示“始终允许”。代码里有 `allowAlways` 数据结构，但 Claude hook 的持久允许机制未验证，所以 `ApprovalContent.alwaysAllow` 被设为 `nil`。

### Claude AskUserQuestion

`AskUserQuestion` 是 Claude 的特殊情况：它不是普通审批，而是挂在 `PermissionRequest` 里的结构化提问工具。

触发条件：

- hook event 是 `PermissionRequest`
- `tool_name == "AskUserQuestion"`
- `tool_input.questions` 能解析出可用问题

展示方式：

- 使用 `QuestionCard`
- 标题默认是 `Claude 需要你确认`
- 每个问题读取：
  - `question` 作为完整题干
  - `header` 作为短标题；缺失时取题干前 12 个字符
  - `multiSelect` 决定单选/多选，缺省为 `false`
  - `options[].label`
  - `options[].description` 作为选项说明
- 每个问题都会追加一个 UI 专用的 `其他` 选项，允许用户输入自由文本

提交行为：

| 用户操作 | VibePet response | 写回 Claude 的 hook output |
|---|---|---|
| 提交完整答案 | `.question(QuestionAnswer)` | `decision.behavior: "allow"` + `decision.updatedInput.questions` + `decision.updatedInput.answers` |
| 没有可用答案/关闭/defer | `.defer` | 空 stdout，退出 0，让 Claude 回到原生提问 |

`updatedInput.answers` 以原始 question text 为 key；VibePet 内部的 `QuestionAnswer` 以 `header` 为 key，编码时会转换。UI 追加的 `其他` 选项不会写回 `updatedInput.questions`，只把用户输入作为答案值写回。

## Codex Hook

Codex 安装 4 个 hook key。安装器把 hook 写入 `hooks.json`，并启用 `[features].hooks = true`。Codex 所有 managed group 都带 `statusMessage: "Managed by VibePet"` 以便卸载时精确移除。

| Hook | 触发时机 | VibePet 事件 | Bubble 展示 | 权限关系 | 宠物状态 |
|---|---|---|---|---|---|
| `SessionStart` | Codex 会话开始 | `sessionStarted` | `status` | 无 | 会话 running；新会话触发 greeting/waving |
| `UserPromptSubmit` | 用户提交 prompt | `activityUpdated` | `status` | 无 | running |
| `PermissionRequest` | Codex 需要权限 | `permissionRequested` | `approval` | 用户允许/拒绝/defer 后回传 Codex | waiting/decide |
| `Stop` | 一轮任务结束 | `sessionCompleted` | `completion` | 无 | completed |

Codex adapter 还兼容解析 `notify` program 的 `agent-turn-complete` payload，但 VibePet 当前安装走的是 `Stop` hook，不是 Codex notify program。

### Codex 审批卡

`PermissionRequest` 展示审批卡。

| Codex tool | VibePet 预览 | 标题 |
|---|---|---|
| `Bash` / `shell` | command | `运行命令` |
| `apply_patch` | fileChange | `修改文件` |
| 其他 | generic | `请求执行 <toolName>` |

按钮行为：

| 用户操作 | VibePet response | 写回 Codex 的 hook output |
|---|---|---|
| `允许一次` | `.approval(.allowOnce)` | `decision.behavior: "allow"` |
| `拒绝` | `.approval(.deny(reason))` | `decision.behavior: "deny"`，默认消息为 `VibePet：用户拒绝了此操作` |
| 关闭/无法展示/defer | `.defer` | 空 stdout，让 Codex 回到原生审批流程 |

当前不展示“始终允许”。Codex 持久允许规则未验证，所以 `alwaysAllow` 也被设为 `nil`。

### Codex 自由输入类请求

Codex hooks 当前不能像 Claude `AskUserQuestion` 那样回填答案。因此 adapter 对自由输入类请求不生成 `question` bubble，而是降级为需要回终端处理的审批卡。

当前识别的自由输入 tool name：

- `AskUserQuestion`

展示方式：

- 审批卡标题：`需在终端处理`
- 风险：`medium`
- `requiresTerminalApproval: true`
- footer 不显示允许/拒绝按钮，只显示：
  - 文案：`此请求需在终端继续处理`
  - 按钮：`回终端处理`

点击 `回终端处理` 会：

1. 尝试跳回终端；
2. 将 action summary 复制到剪贴板；
3. 返回 `.defer`，让 Codex 使用原生流程继续处理。

## Bubble 与阻塞通道

VibePet 内部把 hook payload 归一化为四类 `BubbleContent`：

| BubbleContent | 是否需要响应 | 典型来源 |
|---|---:|---|
| `approval` | 是 | Claude `PermissionRequest`；Codex `PermissionRequest` |
| `question` | 是 | Claude `PermissionRequest + AskUserQuestion` |
| `completion` | 否 | Claude `Stop` / `StopFailure` / `SessionEnd`；Codex `Stop` |
| `status` | 否 | session/activity/notification 类 hook |

只有 `approval` 和 `question` 会进入阻塞决策通道。阻塞期间：

- App 端没有自动倒计时；
- hook 连接等待用户操作；
- CLI/hook 自身 timeout 是最终 fail-open 兜底；
- 如果 App 不可达、socket 失败、pet 隐藏无法展示，都会 defer，不让 Claude/Codex 卡死。

## 决策队列

当一次运行里有很多工具调用时，多个 `approval` / `question` 会进入 `PetController` 的 FIFO 决策队列。

当前行为：

- 只展示队首决策卡；
- 后续决策不覆盖当前卡；
- UI 显示 `还有 N 个待处理`；
- 当前卡处理完后展示下一个；
- 决策期间到来的非交互通知不会覆盖决策卡，只累积通知 badge。

因此当前实现解决了“同时弹多个”的问题，但没有解决“连续很多工具调用导致用户反复点允许”的负担。要降低点击负担，需要额外设计批量确认、短期会话授权、按工具/风险合并、或转回原生权限策略等机制。

## 会话阶段与宠物状态

VibePet 的宠物状态不是直接由 hook key 决定，而是由 `SessionState` 的会话阶段派生。

### SessionPhase

| Phase | 进入来源 | 是否需要用户注意 |
|---|---|---:|
| `running` | `sessionStarted`、普通 `activityUpdated`、审批允许、问题提交、defer 后 resolved | 否 |
| `waitingForApproval` | `permissionRequested` | 是 |
| `waitingForAnswer` | `questionAsked` | 是 |
| `completed` | `sessionCompleted`，或审批拒绝 | 否 |

### SessionPetActivity

| Activity | 条件 | 宠物表现 |
|---|---|---|
| `deciding` | 有任意 session 处于 `waitingForApproval` 或 `waitingForAnswer` | 进入 decide，展示交互卡 |
| `greeting` | 有 running session 尚未打过招呼 | waving/greet |
| `idle` | 无等待，也没有新 running session 需要打招呼 | idle |

### PetVisualState

| Visual state | 条件 | UI 表现 |
|---|---|---|
| `waiting` | 有任何需要用户注意的 session | 宠物高亮等待 |
| `failed` | 可见 session 中存在错误完成 | 失败状态 |
| `running` | 可见 running session 数量大于 0 | running 状态 |
| `idle` | 以上都不满足 | idle |

### PetController 状态

| State | 进入来源 | 实际动画/展示 |
|---|---|---|
| `idle` | 默认或 bubble dismiss 后 | idle |
| `greet` | 新 session running 且未打招呼 | waving |
| `notify` | `completion` / `status` 非交互气泡 | 宠物本体 idle，气泡承载信息 |
| `decide` | `approval` / `question` 等待响应 | waiting |

## 当前产品含义

从用户负担看，问题不在 hook 总数本身，而在阻塞入口的频率：

- Claude 每个需要权限的工具执行前都会触发 `PreToolUse`；
- Codex 每个需要权限的工具执行前都会触发 `PermissionRequest`；
- VibePet 当前对这些请求逐个排队展示；
- “始终允许”在两端都没有启用；
- 因此一次运行中多次 shell、patch、文件写入等操作会导致用户反复确认。

后续如果要降噪，最直接的设计方向是围绕 `approval` / `question` 阻塞通道做策略，而不是减少 session/activity/notification 类 hook。
