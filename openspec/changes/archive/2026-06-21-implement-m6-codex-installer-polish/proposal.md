## Why

M0–M5 让 **Claude Code** 的通知、审批、提问在桌面宠物气泡里闭环。里程碑 M6（PRD US-5 / US-3·US-4 的 Codex 侧 / US-0③）补齐**第二工具 Codex**、**一键安装/卸载 hooks**、**设置页与首启第③步**，并做**发布打磨**（统一主题/错误、KPI 达标），使 VibePet 成为可分发的 MVP。

Codex 与 Claude Code 能力不对等：Codex 的 `PermissionRequest` 审批回路与 `notify(agent-turn-complete)` 完成通知可用，但 hook **不支持回填答案**，故结构化提问**降级**为"回终端处理"。安装必须可预期、可逆、不破坏用户既有配置，且要正确表达 Codex hook 的"已写入≠已生效"（需 `/hooks` trust）。

> **范围决定（2026-06-20，用户确认）**：本变更覆盖 M6-1~M6-6 + M6-7 的代码部分（`BubbleTheme` 集中化、`ErrorPresenter` 统一错误）。**App 签名与公证延后**至后续独立发布动作，不在本变更内执行（仅产出 `Scripts/notarize.sh` 与发布检查清单占位）。除已在文档中记录通过的**抠图/照片基准 KPI（M1-5，已测通过）**外，其余 KPI（端到端闭环、≤500ms 延迟、Fail-open 100%、Codex 审批回路）须经**真实 Claude/Codex 会话**验收达标。

## What Changes

- **CodexAdapter 解析（M6-1）**：`VibePetCore` 新增 `CodexAdapter`，`PermissionRequest` → `.approval`（shell 升权→`.command`、apply-patch→`.fileChange`，复用 M4 `ActionPreview` 组装与 `RiskClassifier`）；`notify(agent-turn-complete)` → `.completion`；提问 / plan-mode 等需输入 → `.approval` 且 `requiresTerminalApproval = true`（降级）。
- **CodexAdapter 回写与提问降级（M6-2）**：`encodeResponse` 把 `allowOnce`/`allowAlways` → allow（`allowAlways` 在 Codex 无持久规则验证时等同本次 allow）、`deny` → deny、`question`/`defer` → decline（不决定，回退原生审批）；回写**幂等**，不假设 VibePet 独占审批流，`requestId` 仅用于自身配对。
- **CLI 适配器路由（M6-1 配套）**：`VibePetHooks` 按工具选择 `CodexAdapter` 或 `ClaudeCodeAdapter`（安装器为 Codex 配置写入带工具标识的 command），fail-open 契约不变。
- **回终端审批气泡（M6-3）**：`ApprovalCard` 在 `requiresTerminalApproval == true` 时不显示允许/拒绝，改为单个"回终端处理"按钮 + 提示（MVP 仅聚焦/复制提示，跳转留 v1.1）。
- **二进制安装到稳定路径（M6-4）**：`VibePetSetup` 把 `VibePetHooks` 拷到 `~/Library/Application Support/VibePet/bin/VibePetHooks`（与 `.app` 解耦），版本落后则重拷；工具配置 command 永远指向该拷贝。
- **manifest 驱动安装/卸载/status（M6-5）**：`install`（幂等、写前展示+备份原配置、写 `install-manifest.json`）/ `uninstall`（按 manifest 精确移除 `writtenHooks`、保留用户其它 hooks）/ `status`（未安装 / 已写入待信任 / 已启用 / 版本落后）；不覆盖用户非 VibePet 条目。Codex 写入采用 **open-vibe-island 做法**（clean-room）：hooks → `~/.codex/hooks.json`（`statusMessage` 标记的 PermissionRequest+Stop），config.toml 仅切 `[features] hooks = true`（按行、table 安全），完成通知用 `Stop` hook（非 `notify`）。
- **Codex hook trust 激活态（M6-5a）**：安装态三类 `notInstalled` / `installedNeedsTrust` / `trustedActive`；Codex 写入后默认 `installedNeedsTrust` 并引导 `/hooks`；首次真实收到 Codex hook 事件 → `trustedActive`；无法自动判断时不得显示"已启用"。
- **设置页与 onboarding ③（M6-6）**：新增设置页（启用工具、一键安装/卸载据 manifest 显示安装态/版本/trust、决策超时、开机自启、生成器选择—MVP 仅本地）；首启第③步只列检测到的工具、各带安装态、可"以后再说"跳过、Codex 待信任显示 `/hooks` 引导。
- **发布打磨（M6-7，代码部分）**：`BubbleTheme` 集中配色/圆角/字体并跟随系统明暗；新增 `ErrorPresenter` 按 §7 错误表统一错误提示。**签名/公证延后**（仅占位脚本+清单）。

## Capabilities

### New Capabilities
- `codex-adapter`: Codex 工具适配——`PermissionRequest` → `.approval`、`notify(agent-turn-complete)` → `.completion`、需输入场景 → `.approval(requiresTerminalApproval)` 降级；`encodeResponse` 的 allow/deny/decline 幂等回写与提问 `defer` 引导回终端。
- `hook-installer`: `VibePetSetup` 的二进制稳定路径拷贝 + manifest 驱动的对称 `install`/`uninstall`/`status`（幂等、写前确认+备份、精确卸载保留用户条目）+ Codex 三态 trust（`notInstalled`/`installedNeedsTrust`/`trustedActive`）。
- `settings-page`: App 设置页——启用工具、据 manifest 一键安装/卸载与安装态/版本/trust 展示、决策超时、开机自启、生成器选择（MVP 仅本地）。
- `error-presentation`: `ErrorPresenter` 按 §7 错误表把生成/安装/桥接错误归一化为可读提示与建议动作（如 `.noSubject`→换一张、Codex 待信任→引导 `/hooks`）。

### Modified Capabilities
- `approval-card`: 新增 `requiresTerminalApproval == true` 的降级形态——不显示允许/拒绝，改为单个"回终端处理"按钮 + 提示（聚焦/复制提示）。既有审批三段布局、风险配色、倒计时 fail-open 要求保持。
- `onboarding-flow`: 第③步"安装 hooks"从占位接入实装——只列检测到的工具（存在 `~/.claude/` 或 Codex 配置才显示）、各带安装态、可跳过、未检测到给可读提示、Codex 待信任显示 `/hooks` 引导。既有①欢迎②生成宠物要求保持。
- `hook-cli`: `VibePetHooks` 按工具选择 `ToolAdapter`（Codex 走 `CodexAdapter`、默认 `ClaudeCodeAdapter`），由 command 工具标识驱动。既有 stdin→adapter→发送、阻塞决策回路、fail-open（连接失败 ≤2s `defer`/decline、无响应超时回退）要求保持。

## Impact

- **新增源码**：`VibePetCore/Adapters/CodexAdapter.swift`；`VibePetSetup/BinaryInstaller.swift`、`VibePetSetup/Paths.swift`、`VibePetSetup/HookInstaller.swift`、`VibePetSetup/InstallManifest.swift`、`VibePetSetup/ClaudeCodeConfigWriter.swift`、`VibePetSetup/CodexConfigWriter.swift`；`VibePetApp/Settings/SettingsView.swift`、`VibePetApp/Settings/HookInstallSection.swift`；`VibePetApp/Common/ErrorPresenter.swift`；`Scripts/notarize.sh`（占位）。
- **修改源码**：`VibePetCore/Bridge/HookRuntime.swift` 与 `VibePetHooks/main.swift`（按工具选 adapter）；`VibePetApp/Bubble/ApprovalCard.swift`（terminal-approval 降级分支）；`VibePetApp/Bubble/BubbleTheme.swift`（集中化+跟随主题）；`VibePetApp/Onboarding/OnboardingFlow.swift`（接入③）；`VibePetSetup/main.swift`（接 CLI 子命令 install/uninstall/status）；可能 `VibePetApp/MenuBar/StatusItemController.swift`（打开设置接线）。
- **新增测试 target**：`Tests/VibePetSetupTests`（需在 `Package.swift` 注册）。
- **复用既有**：`ApprovalContent.requiresTerminalApproval`、`ToolKind.codex`、`ActionPreview`、`RiskClassifier`、`BridgeEnvelope`/`BridgeResponse`（M0/M4 已定义，仅消费）；`ToolAdapter` 协议、`BridgeClient`/`HookRuntime` 阻塞回路与 fail-open（M3/M4）；`ConfigStore`（决策超时、启用工具、生成器 id、首启标记）；`PetImportPanel`（onboarding ②复用）；`BubbleTheme`/`ErrorPresenter` 消费方既有气泡与导入面板。
- **新增/更新测试**：`Tests/VibePetCoreTests/CodexAdapterParseTests.swift`、`CodexAdapterEncodeTests.swift`；`Tests/VibePetSetupTests/InstallerTests.swift`、`CodexHookTrustTests.swift`；`Tests/E2E/CodexApprovalFlowTests.swift`；`Tests/Fixtures/codex/`（`PermissionRequest`/`notify`/`config.toml`/`hooks.json` 样例）；`ApprovalCard` 降级形态与 onboarding③ 的 App 层断言。
- **依赖与守则**：`CodexAdapter`/`InstallManifest`/`ErrorPresenter` 留在 `VibePetCore`/`VibePetSetup`，不导入 AppKit/SwiftUI；UI（设置页、`ApprovalCard`、onboarding）仅在 `VibePetApp`；无第三方依赖、全程不联网、保持本地优先。fail-open 为硬要求——解析/连接失败/用户未响应一律回退工具原生流程；安装器**幂等且不覆盖用户条目**、写前备份。
- **运行时副作用**：安装器**写入用户配置文件**（`~/.claude/settings.json`、Codex `config.toml`/`hooks.json`）并落备份+manifest；卸载按 manifest 精确移除。Codex `PermissionRequest` hook 会阻塞 Codex 直至用户决策或超时（沿用 M4 倒计时）。Codex 写入后须用户在 `/hooks` trust 才生效。
- **明确不做（本变更外）**：App 实际签名与公证（延后，仅产出脚本/清单占位）；Codex `allowAlways` 持久规则（无验证→等同本次 allow）；回终端的真正跳转（v1.1）；多屏位置记忆。
