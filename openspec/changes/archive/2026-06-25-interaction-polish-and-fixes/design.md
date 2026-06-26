## Context

0.3 的会话面板（`session-dashboard-panel`，已归档）落地后，剩余四类打磨集中在决策链路与界面表现：审批/问答卡早期裸气泡观感（C）、Codex 工具执行阶段无状态心跳（D）、强制决策倒计时与"等用户决定"意图冲突（E）、Claude 多主题提问提交丢答（F）。

当前相关现状：
- `BubbleTheme` 已含 dashboard 暗色令牌与 `SessionDashboardProjection.Status` 状态色（面板落地时引入）；C 的统一以此为基础向卡片收敛。
- `PetController` 持有 `decisionTimeout` + `startDecisionTimeout`/`decisionTimeoutTask`；`ApprovalCard`/`QuestionCard` 各自跑 `runCountdown()` 到零 `.defer`；`SettingsView` 有"决策超时"滑块；`AppConfig.decisionTimeoutSeconds` 默认 20。
- `CodexAdapter` 处理 `SessionStart/UserPromptSubmit/PermissionRequest/Stop`，`CodexConfigWriter.managedHookKeys = [PermissionRequest, Stop, SessionStart, UserPromptSubmit]`，缺 `PostToolUse`。
- `QuestionCard.hasAnySelection` 仅要求"至少一个问题已答"即可提交（对照 open-vibe-island `hasCompleteSelection` 的"全部已答"，这是丢答 bug 根因）。

约束：`VibePetCore` 不得引入 UI；fail-open 红线不可破；hook 命令路径单引号；改 `CodexAdapter`/`CodexConfigWriter`/`PetController`/卡片须 `swift test`。

## Goals / Non-Goals

**Goals:**
- C：把卡片样式收敛到统一暗色令牌；宠物窗口加常驻状态点（绿/橙/灰）。
- D：Codex 受管 hook 增加 `PostToolUse`，适配器映射为 `activityUpdated` 心跳，刷新运行中会话的摘要与时间戳。
- E：移除 App 侧决策倒计时；决策挂起至用户响应；删设置项与 `AppConfig` 字段消费；保留 CLI hook 读超时作为唯一兜底。
- F：问答卡提交校验改为"全部问题已答"（freeform 需非空文本）。

**Non-Goals:**
- 不扩展 `ToolKind`、不做进程发现。
- 不补 Codex 失败态 / `SessionEnd`（记为已知限制，留待真实会话验证）。
- 不引入问答全局自由回复框 / `annotations` 写回（open-vibe-island 增强项，超范围）。
- 不改 `session-dashboard` / `pet-quick-switch` 已落地行为。

## Decisions

**D1 — 状态点放在窗口叠加层，源自既有 `PetVisualState`，不入 Core。**
状态点颜色直接复用 `SessionState.petVisualState`（running/waiting/failed/idle）→ 颜色映射，渲染为 `PetView`/窗口的角标叠加。它绝不参与 sprite 命中遮罩或指针路由（守住透明像素 passthrough）。备选：放进 dashboard 面板内——否决，状态点要在面板未打开时也常驻可见。

**D2 — 移除超时采取"删消费、留字段容忍解码"。**
`PetController` 删 `decisionTimeout`/`startDecisionTimeout`/`decisionTimeoutTask`；卡片删 `timeout` 形参与 `runCountdown()`。`AppConfig` 移除 `decisionTimeoutSeconds` 的读写消费，但 `init(from:)` 用 `decodeIfPresent` 容忍旧 `config.json` 里残留该键（不报错、不生效）。备选：硬删字段并迁移旧配置——否决，徒增迁移面，容忍解码更稳。

**D3 — fail-open 兜底下移到 CLI hook 读超时，不改 `HookRuntime`。**
App 不再产生自动 `.defer`；但 dismissal（关卡/宠物隐藏 → `failOpenAllDecisions`）仍 `.defer`。若用户始终不点，最终由 hook 自身 timeout（Codex `PermissionRequest`、Claude command timeout）兜底回落原生流。`hook-installer` spec 据此把"tool 侧 timeout 须超过 App 截止"改述为"timeout 是唯一兜底，须足够长且有限"。`HookRuntime` 既有 `.deferred`（不写 stdout）语义不变。

**D4 — `PostToolUse` 复用既有 `activityUpdated` 通道与 reducer 守卫。**
`CodexAdapter` 新增 `PostToolUse → .activityUpdated`，摘要取 `tool_name` 兜底默认串。`SessionState.apply(.activityUpdated)` 现有守卫 `if !phase.requiresAttention { phase = .running }` 天然保证心跳不清除等待中的审批/问答（满足 spec "不覆盖 active approval"）。安装器在 `managedHookKeys` 末尾加 `PostToolUse`，timeout 取 `stopTimeout` 量级（非阻塞通知）。备选：新增独立 AgentEvent 类型——否决，心跳语义等同活动更新，复用即可。

**D5 — F 仅改提交闸门，收集逻辑不动。**
`QuestionCard.collectAnswer()` 已正确按 header 收全部已答项；bug 只在 `hasAnySelection`。改为 `content.questions.allSatisfy { 每题有有效选择且 freeform 非空 }`，对齐 open-vibe-island `hasCompleteSelection`。写回 `updatedInput.answers`（keyed by question text）逻辑不变。

**D6 — C 主题收敛为纯实现，不新增 spec。**
统一令牌 + 卡片重绘无 spec 级行为变化，仅在 tasks 跟踪；唯一 spec 级 C 变化是状态点（`desktop-pet-window` ADDED）。

## Risks / Trade-offs

- [移除 App 倒计时 → 阻塞 agent 更久] → 决策一直挂起是产品意图；CLI hook timeout 兜底仍在，fail-open 不破；dismissal/宠物隐藏仍即时 `.defer`。
- [`PostToolUse` 改了受管 hook 集 → 已装用户需重装] → 安装幂等检测会因缺键触发重写；onboarding/设置页提示用户重装一次；卸载按 `statusMessage` 精确移除新键。
- [删卡片 `timeout` 形参 → 破坏现有测试/调用点] → `BridgeServerHost`、`PetController`、`ApprovalCardTests`/`QuestionCard` 相关用例需同步；改完跑 `swift test`。
- [状态点叠加误伤命中遮罩] → 叠加层不改 `hitMask`，spec 显式要求 passthrough 不变并加场景验证。
- [`AppConfig` 字段移除影响 `with(...)`/默认值/测试] → 同步 `PetAssetCodecTests`/`AppConfig` 相关用例；保留 `decodeIfPresent` 容忍旧键。
- [两次在 `desktop-pet-window`/`pet-controller` 上做 delta（与已归档面板 change）] → 已基于当前主 spec 复制整块 MODIFIED；归档时按需求头精确合并，无覆盖。
