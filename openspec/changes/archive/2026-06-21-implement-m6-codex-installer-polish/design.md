## Context

M0–M5 已让 Claude Code 四态（status/completion/approval/question）在桌面宠物气泡里闭环：M0 定义归一化数据模型（`BridgeEnvelope`/`BridgeResponse`/`ApprovalContent.requiresTerminalApproval`/`ToolKind.codex` 均已就位）；M3/M4 建立 `VibePetHooks` CLI 阻塞回路、`BridgeClient`/`HookRuntime`、fail-open 超时与 `PetController.decide`；M4 提供 `ActionPreview` 组装与 `RiskClassifier`。

M6 在此之上补三块：①第二工具 **Codex** 适配（`VibePetCore/Adapters/CodexAdapter.swift`），②**安装器** `VibePetSetup`（当前仅 `main.swift` 占位），③**设置页 / onboarding③ / 发布打磨**。`VibePetSetup` 目前无 `Tests/VibePetSetupTests` target，需在 `Package.swift` 注册。

约束：`VibePetCore`/`VibePetSetup` 不得导入 AppKit/SwiftUI；fail-open 为硬要求；安装器写用户配置须幂等、可逆、备份、不覆盖用户条目；全程本地、不联网；Codex `notify` 仅 `agent-turn-complete`、hook 不支持回填答案、写入后需 `/hooks` trust 才生效。

## Goals / Non-Goals

**Goals:**
- Codex `PermissionRequest` 审批回路 + `notify` 完成通知可用；提问降级为 `requiresTerminalApproval`「回终端处理」。
- `VibePetSetup` 二进制拷到稳定路径 + manifest 驱动的对称 `install`/`uninstall`/`status`，对 Claude Code 与 Codex 均幂等、备份、精确卸载、不覆盖用户条目；Codex 三态 trust。
- 设置页（启用工具/安装态/超时/自启/生成器）与 onboarding③ 实装；统一 `BubbleTheme` 与 `ErrorPresenter`。
- 除已通过的抠图 KPI 外，端到端闭环 / ≤500ms / Fail-open 100% / Codex 审批回路经真实会话验收。

**Non-Goals:**
- App 实际签名与公证（延后；仅 `Scripts/notarize.sh` + 发布清单占位）。
- Codex `allowAlways` 持久规则（未验证 → 等同本次 allow）；回终端真正跳转（v1.1）；多屏位置记忆。
- 重写 M0 的 TD-1/TD-2 socket I/O（已在 M3 处理范围，不在 M6）。

## Decisions

### D1 · CLI 按工具选择 adapter，由 command 工具标识驱动
`HookRuntime` 当前固定默认 `ClaudeCodeAdapter`。M6 让 `VibePetHooks` 接受工具标识（CLI 参数 `--tool codex`，缺省=claudeCode）选择 `CodexAdapter`/`ClaudeCodeAdapter`。安装器为 Codex 配置写入的 command 带该标识，Claude 配置不带。
- **为何不靠事件自动嗅探**：两工具事件 JSON 形态可区分，但显式标识更稳、零歧义、便于 status/卸载对账；嗅探在 schema 漂移时易误判。
- 既有 `hook-cli` 规范本就写「select the appropriate `ToolAdapter`」，本决策把"appropriate"具体化，不改既有 stdin→parse→send 与阻塞回路结构。

### D2 · `defer`/`decline` 两工具均为空 stdout，`HookRuntime` 不变（实现订正）
**早先假设**：Codex 的 decline 是非空 JSON，需让 CLI 经 `adapter.encodeResponse(.defer, for:)` 取工具原生输出。
**M6-1 spike 订正（2026-06-20）**：Codex 的 **decline / 不决定 = 不输出任何内容**（plain text 被忽略 → Codex 走原生审批流），与 Claude 的 `defer`（无 JSON + `exit 0`）**输出一致**。因此：
- `HookRuntime` 既有的 `.deferred`（fail-open 时不写 stdout）**已正确实现 Codex decline**——M6 **不改** `HookRuntime`（保持 surgical）。
- `CodexAdapter.encodeResponse(.defer)` 与 `.question` 均返回空 `Data`（decline）；App 显式回传 `.defer` 经成功路径 `adapter.encodeResponse(.defer, for:)` 也得空 → `main.swift` 仅在非空时写 stdout，两工具一致。
- 详见 `Tests/Fixtures/codex/codex-spike-notes.md`。

### D3 · CodexAdapter 复用 M4 组装，回写幂等且不独占
- 解析：`PermissionRequest`（shell 升权→`.command`、apply-patch→`.fileChange`）复用 `ActionPreview` 组装 + `RiskClassifier`；`notify(agent-turn-complete)`→`.completion`；提问/plan-mode 等需输入→`.approval(requiresTerminalApproval=true)`。
- 回写：`allowOnce`/`allowAlways`→allow；`deny`→deny；`question`/`defer`→decline。MVP 只用 allow/deny/decline（`ask`/`continue:false` 解析但不支持）。
- **幂等/不独占**：Codex 可并发触发多个匹配 hook；回写不假设 VibePet 独占，`requestId` 仅自身配对、非全局锁；多 hook 时 deny 优先由 Codex 侧裁决，VibePet 只产出自己的决策。

### D4 · manifest 驱动安装，三件套对称
单一事实源 `~/Library/Application Support/VibePet/install-manifest.json` 记录每工具 `installed`/`activationState`/`settingsPath`/`writtenHooks`/`backupPath` 与 `hookBinaryVersion`。
- `install`：检测配置→写前展示将改动文件/二进制/备份并经 App 确认→备份原配置→拷贝/升级 `bin/VibePetHooks`→把 hook 条目写入工具配置（command 指向稳定路径）→写 manifest。幂等：已装跳过、仅版本落后重拷；目标键已有用户非 VibePet 条目则**追加不覆盖**。
- `uninstall`：读 manifest 只移除 `writtenHooks` 记录条目，保留用户其它 hooks；删 `bin/VibePetHooks` 与 manifest 对应项。
- `status`：读 manifest + 校验二进制版本 + 激活态 → 每工具返回 `未安装/已写入待信任/已启用/版本落后`。
- **为何 manifest 而非字符串猜测**：精确卸载、幂等、可对账，借鉴 open-vibe-island 的**模式**（clean-room 实现，不复用其 GPL 源码）。
- **配置写入器分工**：`ClaudeCodeConfigWriter`（JSON：`~/.claude/settings.json` 的 `hooks.PreToolUse/Stop/Notification`）、`CodexConfigWriter`（见 D4a）。两者只负责"注入/精确移除 VibePet 条目 + 备份"，由 `HookInstaller` 编排。
- **`managedFiles`**：`ToolConfigWriter` 暴露 `managedFiles`（默认 `[configURL]`，Codex 覆盖为 `[config.toml, hooks.json]`），`HookInstaller` 写前对每个存在的文件落备份。

### D4a · Codex 写入按 open-vibe-island 方式（用户指定）——hooks.json + `[features]` flag，不写 TOML hooks 表、不用 notify
**早先方案**：`CodexConfigWriter` 写 `config.toml` 的 `[[hooks.PermissionRequest]]` 表 + `notify` 程序。
**订正（用户："和 open-vibe-island 一样"，clean-room 复刻其做法、不复用 GPL 源码）**：
- **hooks → `~/.codex/hooks.json`（JSON）**：`{"hooks":{Event:[group]}}`，managed group 的 hook 带 `statusMessage:"Managed by VibePet"` 标记，command = `'<binaryPath>' --tool codex`。注册 **PermissionRequest**（审批）+ **Stop**（完成通知）。按 `statusMessage`/binaryPath 精确识别 → 幂等安装、精确卸载。
- **config.toml 仅切 `[features] hooks = true`**：按行编辑（找 `[features]` 段插入/改键，缺失则在文件尾追加 `[features]` 表）。**只往 table 加键、绝不在 table 后加 root key**——规避 TOML "root keys must precede tables" 陷阱（这正是早先 notify 方案不可行的原因）。无第三方 TOML 依赖（符合 CLAUDE.md）。
- **完成通知改用 `Stop` hook**（stdin，`last_assistant_message`）而非 `notify` 程序：`CodexAdapter` 增 `Stop`→`.completion`；`notify(agent-turn-complete)` 解析保留（robust，但不再注册）。
- 参考：open-vibe-island `Sources/OpenIslandCore/CodexHooks.swift` / `CodexHookInstaller.swift`（仅借做法）。

### D5 · Codex trust 三态与 `trustedActive` 运行时证据
`activationState ∈ {notInstalled, installedNeedsTrust, trustedActive}`。Codex 写入后默认 `installedNeedsTrust`（无法自动读 `/hooks` trust），设置页/CLI 显示「已写入，需在 Codex `/hooks` 确认」。**首次真实收到 Codex hook 事件**时 App 把 manifest/运行态缓存标记 `trustedActive`。无证据时**不得**显示「已启用」。Claude Code 写入即视为 `trustedActive`（无 trust 门槛）。
- **运行态→持久化通路**：App 的 `BridgeServerHost` 收到 `source.tool == .codex` 的首个 envelope → 通过 `InstallManifest` 写回 `trustedActive`（幂等）。

### D6 · `requiresTerminalApproval` 在 `ApprovalCard` 内分支，不新增卡片类型
`ApprovalCard` 在 `requiresTerminalApproval == true` 时隐藏允许/拒绝，改渲单个「回终端处理」按钮 + 提示（MVP 聚焦/复制提示，真正跳转 v1.1）。回传仍走既有审批连接，但语义为 `defer`（引导用户回终端原生处理）。
- **为何复用而非新卡**：Codex 提问/plan-mode 与审批共用三段骨架与锚定，只是底部按钮区不同；新增卡片类型徒增表面积（规范 §5.3.4 末已如此约定）。

### D7 · 发布打磨：集中 `BubbleTheme`、新增 `ErrorPresenter`
`BubbleTheme` 集中配色/圆角/字体并跟随系统明暗（`@Environment(\.colorScheme)`）。`ErrorPresenter`（`VibePetCore` 或 `VibePetApp/Common`，不依赖 UI 框架的部分留 Core）把 §7 错误表归一为 `(message, suggestedAction)`——`GenError.noSubject`→换一张、安装失败→可读原因+回滚提示、Codex 待信任→`/hooks` 引导。签名/公证仅产 `Scripts/notarize.sh` + 清单占位，不执行。

## Risks / Trade-offs

- **Codex hook trust 无法自动读取** → 用三态 + 运行时事件证据兜底；设置页明确"待信任"，绝不把"已写入"显示成"已启用"（D5）。
- **安装器写用户配置出错破坏 Claude/Codex** → 写前必备份 + manifest 记录 `backupPath`；`uninstall` 精确移除；对样例 `settings.json`/`config.toml`/`hooks.json` 的注入与移除写单测（幂等、备份、保留用户条目）。失败时回滚到备份。
- **Codex 多 hook 并发、非独占** → 回写幂等、`requestId` 仅自身配对（D3）；不假设唯一匹配 hook。
- **Codex `notify` 仅 `agent-turn-complete` / 无答案回填** → 完成通知可用、提问降级回终端（D6），不承诺气泡内作答。
- **签名/公证延后** → 本变更不产可分发签名包；以脚本+清单占位，发布动作单列。验收时明确标注"未签名"。
- **真实会话依赖** → 端到端/延迟/fail-open KPI 需在本机装到 `~/.claude/settings.json` 与 Codex 配置后手动跑真实会话；抠图 KPI 已记录通过、不重复跑。
- **`Package.swift` 新增 `VibePetSetupTests` target** → 确保 `swift build && swift test` 仍绿；避免引入对 App-only 符号的依赖（Setup/Core 不碰 UI）。

## Migration Plan

1. 数据模型零迁移（M0 已含 `ToolKind.codex`/`requiresTerminalApproval`）。
2. 安装器对用户的破坏性写入：先备份 → 写 → 写 manifest；提供 `uninstall` 回滚；先以 fixture/临时目录单测，再本机手动 `install`。
3. 旧 hook 二进制：`status` 检出版本落后 → `install` 仅重拷 `bin/VibePetHooks`，配置不重写。
4. 回滚：`uninstall` 按 manifest 精确移除并恢复；manifest 损坏时以 `backupPath` 兜底。

## Open Questions

- Codex `config.toml` 的 hooks/`notify` 精确键路径与多条目合并语义，以 `Tests/Fixtures/codex/` 真实样例为准（M6-1/M6-5 落地时核对官方文档 https://developers.openai.com/codex/hooks）。
- `allowAlways` 在 Codex 是否有持久规则可写——未验证前等同本次 allow（不作硬依赖）。
- `ErrorPresenter` 落 `VibePetCore` 还是 `VibePetApp/Common`：纯文案映射留 Core（可单测、不依赖 UI），展示留 App。实现时定。
