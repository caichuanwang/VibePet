## 1. CodexAdapter 解析（M6-1）

- [x] 1.1 新增 Codex 样例 fixture：`Tests/Fixtures/codex/permission-request-shell.json`、`permission-request-apply-patch.json`、`notify-agent-turn-complete.json`、`permission-request-ask-question.json`（降级，原计划名 `input-required.json`）；+spike 笔记 `codex-spike-notes.md`
- [x] 1.2 写解析单测 `Tests/VibePetCoreTests/CodexAdapterParseTests.swift`（先红）：`PermissionRequest`→`.approval`（shell→`.command`、apply-patch→`.fileChange`，经 `RiskClassifier`，`requiresTerminalApproval==false`）；`notify(agent-turn-complete)`→`.completion`（`needsResponse==false`）；其它 notify→`nil`；需输入→`.approval(requiresTerminalApproval==true)` 且非 `.question`
- [x] 1.3 实现 `VibePetCore/Adapters/CodexAdapter.swift` 的 `tool == .codex` 与 `parseEvent(stdin:env:)`，复用 M4 `ActionPreview` 组装与 `RiskClassifier`，至 1.2 全绿（8 tests）

## 2. CodexAdapter 回写与提问降级（M6-2）

- [x] 2.1 写回写单测 `Tests/VibePetCoreTests/CodexAdapterEncodeTests.swift`（先红）：`allowOnce`/`allowAlways`→allow、`deny`→deny、`question`/`defer`→decline；断言幂等、`requestId` 仅自身配对；`ClaudeCodeAdapter.encodeResponse(.defer)` 仍返回空（保持既有 no-JSON 行为）
- [x] 2.2 实现 `CodexAdapter.encodeResponse(_:for:)`（allow/deny/decline，MVP 不发 `ask`/`continue:false`），至 2.1 全绿（9 tests）。**订正**：Codex decline = 空 stdout（同 Claude），故 `.question`/`.defer` 均返回空 `Data`

## 3. CLI 适配器路由与 tool-native defer（hook-cli, M6-1 配套）

- [x] 3.1 写单测 `Tests/VibePetCoreTests/HookInvocationTests.swift`（先红）：按 `--tool` 标识选 `CodexAdapter`/`ClaudeCodeAdapter`（缺省=claude）；`--notify` 时从 argv 取载荷、否则 stdin（6 tests）
- [x] 3.2 修改 `VibePetHooks/main.swift`（`HookInvocation` 选 adapter + notify argv 取数）。**订正**：Codex decline = 空 stdout，`HookRuntime` 既有 `.deferred`（不写 stdout）已正确实现 → **未改** `HookRuntime`（surgical）；既有 hook-cli 通知/阻塞/fail-open 单测仍绿（全套 179 tests 0 fail）

## 4. 回终端审批气泡（approval-card, M6-3）

- [x] 4.1 写 App 层断言：`ApprovalCardTests`（`footerMode(for:)`→`.terminal`/`.decision`、`terminalResponse == .defer`）+ `NotificationBubbleFlowTests.testTerminalApprovalResolvesAsDeferOnHandleInTerminal`（presentApproval 携 `requiresTerminalApproval`，fire `.defer` 解析为 `.defer`、回 idle、dismiss）（先红）
- [x] 4.2 在 `VibePetApp/Bubble/ApprovalCard.swift` 增 `requiresTerminalApproval` 降级分支：`footerMode` 切换；terminal footer = 提示 + 单个「回终端处理」按钮（复制 `ActionPreview` 文本到剪贴板 + `decide(.defer)`），至 4.1 全绿（20 tests）

## 5. 安装器：二进制稳定路径（hook-installer, M6-4）

- [x] 5.1 新增 `Tests/VibePetSetupTests` target 到 `Package.swift`（依赖 `VibePetCore`；**订正**：安装逻辑放 `VibePetCore/Install/`，因 `InstallManifest` 需被 App+Setup 共享、且复用 repo "逻辑在 Core、可执行薄壳" 惯例）
- [x] 5.2 写单测 `Tests/VibePetSetupTests/BinaryInstallerTests.swift`（先红）：拷到 `…/VibePet/bin/VibePetHooks`、版本落后/二进制缺失重拷、同版本跳过、可执行位、稳定路径非包内（用 `applicationSupportRoot` 临时目录隔离）
- [x] 5.3 实现 `VibePetCore/Install/InstallPaths.swift`、`BinaryInstaller.swift`（+`VibePetCore.hookBinaryVersion`），至 5.2 全绿（6 tests）

## 6. 安装器：manifest 驱动 install/uninstall/status（hook-installer, M6-5）

- [x] 6.1 新增 fixture `Tests/Fixtures/codex/config.toml`、`Tests/Fixtures/codex/hooks-with-user.json`、`Tests/Fixtures/claude/settings-with-user-hooks.json`（含用户自有 hooks 用于"不覆盖"断言）
- [x] 6.2 写单测（先红）：`InstallManifestTests`（默认/往返）、`ClaudeCodeConfigWriterTests`（注入/保留用户/幂等/精确卸载）、`CodexConfigWriterTests`、`HookInstallerTests`（install 幂等、备份记 `backupPath`、追加不覆盖、写 manifest；uninstall 只移除 `writtenHooks` 保留用户 hooks、删二进制与 manifest 项；`status` 未安装/已写入待信任/已启用/版本落后）
- [x] 6.3 实现 `VibePetCore/Install/`：`InstallManifest.swift`、`ToolConfigWriter.swift`、`ClaudeCodeConfigWriter.swift`（JSON）、`CodexConfigWriter.swift`、`HookInstaller.swift`（编排），至 6.2 全绿。**订正（用户指定"和 open-vibe-island 一样"）**：Codex 不写 config.toml hooks 表/不用 notify——hooks 写 `~/.codex/hooks.json`（JSON，`statusMessage` 标记），config.toml 仅按行切换 `[features] hooks = true`（table 安全，规避 root-key 顺序陷阱）；完成通知用 `Stop` hook（CodexAdapter 已加 `Stop`→`.completion`）；command 带 `--tool codex`
- [x] 6.4 接 `VibePetSetup/main.swift` 子命令 `install`/`uninstall`/`status`（unscoped install 仅装检测到的工具；Codex 提示 `/hooks` 信任）。**注**：真实安装验证留 10.2 手工（`homeDirectoryForCurrentUser` 忽略 `$HOME`，不在本机跑真实 install）

## 7. Codex hook trust 激活态（hook-installer, M6-5a）

- [x] 7.1 写 `Tests/VibePetSetupTests/CodexHookTrustTests.swift`（先红）：Codex 写入默认 `installedNeedsTrust`；`installedNeedsTrust → trustedActive` 转换；无证据不显示"已启用"；Claude 写入即 active（4 tests）
- [x] 7.2 `InstallManifest` 落 `activationState` 三态 + `InstallManifestStore.markTrustedActive(tool:)`（幂等）；App `BridgeServerHost` 收到首个 `source.tool == .codex` envelope 时幂等标记 `trustedActive`（+`NotificationBubbleFlowTests.testCodexEventMarksHookTrustActive`），至 7.1 全绿

## 8. 设置页与 onboarding③（settings-page / onboarding-flow, M6-6）

- [x] 8.1 写 App 层断言 `Tests/VibePetAppTests/HookInstallCoordinatorTests.swift`（先红）：rows 反映检测/状态、install→enabled、Codex install→`installedNeedsTrust` 且 `notice` 含 `/hooks`（writers 注入临时目录，绝不碰真实配置）+ Core `ToolStatusesTests`（detected 过滤 backbone）
- [x] 8.2 实现 `VibePetApp/Settings/`：`HookInstallCoordinator`（包 Core 安装器、解析 bundled VibePetHooks、`ErrorPresenter` 错误）+ `HookInstallSection`（按工具安装态/安装卸载/更新、Codex `/hooks` 引导）+ `SettingsView`（启用工具、决策超时、开机自启 `SMAppService`、生成器仅本地，`ConfigStore` 持久化）；Core 加 `HookInstaller.toolStatuses()` + `ToolConfigWriter.toolDetected()`
- [x] 8.3 `OnboardingFlow` 接入③（`HookInstallSection(detectedOnly:true)` + 「以后再说」/「完成」+ 未检测提示）；`main.swift` `presentSettings()` 用 `SettingsView`、onboarding 传 coordinator；菜单「打开设置」已接 `openSettings`（M2 既有），至 8.1 全绿（manual-demo 渲染）

## 9. 发布打磨：主题与错误统一（error-presentation, M6-7 代码部分）

- [x] 9.1 写 `Tests/VibePetCoreTests/ErrorPresenterTests.swift`（先红）：`GenError.noSubject`→换一张/重试、其它 GenError 可读、Codex 待信任→`/hooks` 引导、enabled/notInstalled 无错、安装失败→可读原因+备份回滚提示
- [x] 9.2 实现 `VibePetCore/Common/ErrorPresenter.swift`（纯映射 `PresentedError`，留 Core 可单测），至 9.1 全绿（5 tests）
- [x] 9.3 `BubbleTheme` 已集中且用自适应系统色（`windowBackgroundColor`/`.primary`/`.secondary`/`systemRed/Orange`），自动跟随明暗；所有卡片已用其 token——**无需改动**（surgical）
- [x] 9.4 新增 `Scripts/notarize.sh`（占位，`exit 1` 不执行）+ `docs/RELEASE-CHECKLIST.md`（签名/公证延后、KPI 真机验收清单）

## 10. 端到端与验收（M6-2/M6-5a/M6-7 验收）

- [x] 10.1 `Tests/E2E/CodexApprovalFlowTests.swift`：CodexAdapter 经真实 `HookRuntime`+`BridgeServer` 往返 deny/allow/defer(decline 空输出)；App 未运行 ≤2s decline；**真实二进制 `--tool codex` 子进程**选 CodexAdapter 并回写 allow（5 tests）
- [ ] 10.2 **（手工，待用户）** 本机安装到真实 `~/.claude`/`~/.codex` 跑真实 Claude/Codex 会话验收：端到端闭环、≤500ms、Fail-open 100%、Codex 审批回路与提问降级、`installedNeedsTrust → trustedActive`。**不在本环境执行**（`homeDirectoryForCurrentUser` 忽略 `$HOME`，会写真实配置）——见 `docs/RELEASE-CHECKLIST.md`
- [x] 10.3 `swift test` 全绿（226 tests，0 失败）；KPI 记录入 `docs/RELEASE-CHECKLIST.md`（抠图/照片基准 M1-5 已通过，引用既有结论）；签名/公证标注"延后"

## 11. 文档与归档

- [ ] 11.1 同步 `openspec/specs/`（由 `/opsx:archive` 执行）：新增 `codex-adapter`/`hook-installer`/`settings-page`/`error-presentation`，更新 `approval-card`/`onboarding-flow`/`hook-cli`。**留待归档步骤**
- [x] 11.2 更新 `docs/VibePet-MVP-任务拆解.md`：新增 TD-5（installer 真实写入只能手工验证 + 签名/公证延后）与 M6 实现状态注
