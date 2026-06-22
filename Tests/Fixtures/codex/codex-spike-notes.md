# Codex adapter — schema spike notes (M6-1 / M6-2)

> 日期：2026-06-20。来源：Codex 官方 hooks 文档 https://developers.openai.com/codex/hooks
> 与 config/notify 参考 https://developers.openai.com/codex/config-reference 。
> 配套实现：`VibePetCore/Adapters/CodexAdapter.swift`、`VibePetCore/Bridge/HookInvocation.swift`。

## 两条投递通道（都以 `Data` 进 `parseEvent`）

1. **`PermissionRequest` hook**（JSON 走 **stdin**）
   - 公共字段：`session_id`、`transcript_path`、`cwd`、`hook_event_name`、`model`、`permission_mode`。
   - 专有字段：`turn_id`、`tool_name`（`Bash` / `apply_patch` / MCP 名）、`tool_input`（`Bash`/`apply_patch` 用 `tool_input.command`；MCP 传全部参数）、`tool_input.description`（可空，别依赖）。
   - 注册：`config.toml` 的 `[[hooks.PermissionRequest]]`（或 `hooks.json`）；`command` 指向稳定路径，附 `--tool codex`。
   - 全套生命周期事件：SessionStart / SubagentStart / PreToolUse / PermissionRequest / PostToolUse / PreCompact / PostCompact / UserPromptSubmit / SubagentStop / Stop。**无** `Notification` / `agent-turn-complete` hook 事件。

2. **`notify` 程序**（`agent-turn-complete`，JSON 作为 **argv `$1`**，不是 stdin）
   - 载荷：`{"type":"agent-turn-complete","turn-id":...,"thread-id":...,"cwd":...,"input-messages":[...],"last-assistant-message":"..."}`。
   - 注册：`config.toml` 顶部 `notify = ["…/VibePetHooks","--tool","codex","--notify"]`（root key 须在任何 table 之前；`notify` 是 user-level，project-local `.codex/config.toml` 会被忽略）。
   - CLI 据 `--notify` 从最后一个 argv 取 JSON 喂给 adapter（见 `HookInvocation.eventData`）。

## 回写（仅 `PermissionRequest`）

- allow：`{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
- deny ：`{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"…"}}}`
- **decline / 不决定 = 不输出任何内容**（plain text 会被忽略）→ Codex 走原生审批流。多 hook 时 **any deny wins**，否则 allow 放行。
- `updatedInput` / `updatedPermissions` / `interrupt` **当前 fail-closed**，**不能**返回。

## 与设计的两处订正（已记录）

1. **Codex 的 `defer`/`decline` = 空 stdout**，与 Claude 的 `defer`（无 JSON + exit 0）**输出一致**。
   - 因此 `HookRuntime` 的既有 `.deferred`（不写 stdout）**已正确实现 Codex decline**——M6 **不需要**改 `HookRuntime`（订正 design.md D2 早先"Codex decline 为非空 JSON"的假设）。
   - `CodexAdapter.encodeResponse(.defer)` 与 `.question` 均返回空 `Data`（decline）。

2. **`requiresTerminalApproval` 降级触发条件为暂定（unverified）**。
   - Codex 的 `PermissionRequest` 本质是二元 allow/deny；官方 hooks 文档**没有**结构化提问/plan 输入事件。
   - 现实现：当 `tool_name ∈ {"AskUserQuestion"}`（镜像 Claude 命名）时降级为 `.approval(requiresTerminalApproval=true)`。这是**占位假设**，待真实 Codex 会话核对后调整 `CodexAdapter.freeformInputTools`。
   - 兜底：任何无法判定的 Codex 事件 → `parseEvent` 返回 `nil`（忽略）或 decline，绝不卡住——fail-open 成立。

## 安装写入方式（M6-5，用户指定"和 open-vibe-island 一样"，复刻其做法）

- **hooks → `~/.codex/hooks.json`（JSON）**，不写 `config.toml` 的 `[[hooks.*]]` 表。managed group 的 hook 带 `statusMessage:"Managed by VibePet"`，command = `'<binaryPath>' --tool codex`。注册 **PermissionRequest**（审批）+ **Stop**（完成）。
- **config.toml 仅切 `[features] hooks = true`**（按行编辑，table 安全；规避 root-key 顺序陷阱——这也是放弃 `notify=[...]` 追加方案的原因）。无第三方 TOML 依赖。
- **完成通知用 `Stop` hook**（`last_assistant_message`），不用 `notify` 程序。`CodexAdapter` 已加 `Stop`→`.completion`；`notify(agent-turn-complete)` 仍解析（robust）但不注册。
- 识别/卸载靠 `statusMessage` 标记，精确移除、保留用户（含 OpenIsland）其它 hooks；**不动 config.toml 已有的 `[features] hooks` 用户值**（enableFeature 幂等设 true）。
- 参考：open-vibe-island `Sources/OpenIslandCore/CodexHooks.swift`、`CodexHookInstaller.swift`、`CodexHookInstallationManager.swift`（可自由查阅参考）。
- ⚠️ **本机 `homeDirectoryForCurrentUser` 忽略 `$HOME`**：真实 install 会写真实 `~/.codex`、`~/.claude`。验证只走 `VibePetSetupTests`（注入临时目录）；真实安装是 10.2 手工步骤。

## 待真实会话验证（留给 M6-2 E2E / M6-5）

- apply_patch 补丁信封多文件 / 重命名 / 删除场景的 path 与增删行计数（现为轻量解析：取首个 `*** … File:` 路径，按行首 `+`/`-` 计数）。
- `notify` 载荷是否稳定含 `cwd`（已知 issue openai/codex#4005，部分版本才有）；无 `cwd` 时 `projectName` 退化为空。
- `config.toml` / `hooks.json` 精确键路径与多条目合并（M6-5 安装器落地时核对）。
