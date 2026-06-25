## Why

VibePet 0.2 的会话模型已经能够把审批、提问、完成和状态消息归并到稳定会话，但用户看到气泡后仍无法直接回到产生该事件的终端窗口。终端跳回需要在 hook 发生时捕获“当前终端 session”这一短暂信号，并在 App 侧提供 best-effort 跳转，否则审批/提问场景仍会迫使用户手动查找窗口。

## What Changes

- 新增终端跳回能力：所有 approval、question、completion、status 气泡/卡片都可以通过双击正文跳回来源终端。
- 精确支持 iTerm、Terminal.app、Ghostty、cmux、VS Code；其他终端按 best-effort 激活 App 或打开 cwd 兜底。
- hook 侧在 fail-open 前提下捕获 `JumpTarget` 初值：iTerm/Terminal 始终尝试 focused-terminal locator，Ghostty 仅在安全 hook 时刻尝试，cmux/VS Code 使用环境与 cwd。
- App 侧新增轻量 resolver，每 2s 只校正 Ghostty 与 Terminal.app 的 live 会话 jump target，作为 hook 捕获之外的安全网。
- App 侧新增 `TerminalJumpService`，按 terminal app 分派 AppleScript、cmux socket、VS Code CLI 或打开 cwd 的兜底链。
- 更新 terminal-approval 卡片的“Handle in terminal”行为，使它在 defer 到原生流程时也尝试跳回来源终端。
- 维持 fail-open：locator、resolver、跳转失败、未授权、超时、App 未运行或缺失 jump target 都不得阻塞 hook 或打断 Claude Code/Codex 原生流。

## Capabilities

### New Capabilities
- `terminal-jumpback`: 终端识别、hook-time jump target 捕获、Ghostty/Terminal 校正、终端分派跳转、双击气泡跳回和 best-effort 兜底。

### Modified Capabilities
- `session-model`: `JumpTarget` 从占位透传模型扩展为终端跳回定位模型，并允许 reducer 接收校正后的 jump target。
- `bridge-protocol`: `SourceInfo.jumpTarget` 的语义从可选透传字段收紧为 hook 捕获的终端跳回初值，仍保持旧包缺字段兼容。
- `hook-cli`: hook 解析必须在 bounded、fail-open 的前提下附加 jump target，不得因为 locator 失败影响原生流程。
- `speech-bubble`: 状态与完成气泡正文支持双击跳回，不影响单击关闭、hover 暂停或自动消失。
- `approval-card`: 审批卡片正文支持双击跳回；terminal-approval 降级表单的“Handle in terminal”尝试跳回后仍以 defer 解决。
- `question-card`: 提问卡片正文支持双击跳回，不影响选项选择、freeform 输入、提交或倒计时 defer。
- `pet-controller`: 气泡/卡片展示管线必须保留 source jump target 并注入跳转服务，使所有内容类型能够触发跳回。

## Impact

- `VibePetCore`: `JumpTarget` 字段与 Codable 兼容性、adapter 侧 terminal app 推断、TTY 捕获、可注入 focused-terminal locator、hook event gate。
- `VibePetHooks`: 继续通过 `parseEvent(stdin:env:)` 使用 adapter 输出 envelope；locator 失败或超时必须空错退化。
- `VibePetApp`: 新增 `TerminalJumpService`、`TerminalJumpTargetResolver`，接入 session monitoring loop、PetController、SpeechBubble、ApprovalCard、QuestionCard。
- 测试：`JumpTarget`/`SourceInfo` 编解码、terminal app 推断、TTY 回退、locator gate、resolver 匹配、jump service 分派与兜底链、双击触发；仅使用注入闭包和单元测试，不做真实终端/installer 冒烟。
- 约束：保持 `VibePetCore` UI-independent，不引入 AppKit/SwiftUI；不新增网络、遥测或第三方依赖；所有系统副作用必须可注入并 fail-open。
