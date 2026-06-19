## Context

M0 定义了归一化协议（`ApprovalContent` / `ActionPreview` / `RiskLevel` / `AlwaysAllowOption` / `BridgeResponseEnvelope` / `ApprovalDecision` 已就位），M3 打通了 hook CLI ↔ App 的单向通知链路并加固了传输层。关键现状：`BridgeServer.Handler` 已是 `@Sendable (BridgeEnvelope) async throws -> BridgeResponseEnvelope`，传输层在同一连接上写回 handler 的返回值，且连接读写已迁出 Swift 协作池、`BridgeClient` 已有连接/读取超时——**M4 所需的阻塞回传原语全部就位，本里程碑不改传输层**。

但当前 `BridgeServerHost` 的 handler 对**所有** envelope 都立即回 `.defer`（M3 通知态只需展示、不需回传）。M4 的核心是让 `needsResponse == true` 的审批事件走真实回传：CLI 发送后阻塞等待 → App `decide` 态弹审批气泡 → 用户点按 → 经同一连接回传 `BridgeResponseEnvelope`（`requestId` 配对）→ CLI 回写 stdout 让 Claude Code 真实放行/取消。

约束：`VibePetCore` 不得 import AppKit/SwiftUI；全程不联网；**fail-open 是硬要求**——解析失败/连接失败/用户未响应/App 崩溃一律让 Claude Code 回退原生确认，绝不卡住工具。

## Goals / Non-Goals

**Goals:**
- `ClaudeCodeAdapter` 解析 `PreToolUse`（非 AskUserQuestion）→ `.approval`，组装 `ActionPreview`（command/fileChange/fileRead/network/generic）。
- `RiskClassifier`（Core、数据驱动、纯函数）把工具名+命令模式归一为 `RiskLevel`，危险模式 → `.high`。
- `encodeResponse` 审批回写：`deny`→deny+reason、`allowOnce`→allow、`defer`→无 JSON+exit 0；字节级与 exit 语义单测。
- CLI 决策类阻塞回路 + 分层 fail-open 计时（连接失败 ≤2s、用户未响应到点 `defer`）。
- `PetController.decide` 态 + `ApprovalCard` 三段布局 + 风险配色/默认焦点 + 倒计时。
- `BridgeServerHost` 对响应类 envelope await 用户决定后回传，`requestId` 配对。
- 多气泡队列与并发堆叠（`requestId` 独立、优先级 `decide`>`notify`>`greet`）。
- 真实 Claude Code 会话端到端：气泡 ≤500ms、拒绝真实取消、允许真实放行。

**Non-Goals:**
- `AskUserQuestion` → `.question` 解析、`QuestionCard`、`updatedInput` 回写（M5）。
- CodexAdapter 审批/降级（M6）。
- 安装器、设置页、`allowAlways` 持久规则的产品化（M6；M4 只验证机制是否可落地）。
- 改动 `bridge-protocol` 或 `bridge-transport`（仅消费 M0 模型 + M3 传输原语）。

## Decisions

### D1 · `BridgeServerHost` 改为 await 用户决定再回传，复用现有 async handler（传输层不改）
现状 handler 对所有 envelope 立即回 `.defer`。
- **决策**：handler 内分流——`content.needsResponse == false` 维持 M3 行为（路由展示后回 `.defer`，CLI 已单向关闭连接）；`needsResponse == true` 则 hop 到 `MainActor` 让 `PetController` 进入 `decide` 并弹 `ApprovalCard`，然后 `await` 用户决定（或超时），把结果包成 `BridgeResponseEnvelope(requestId:, response:)` 返回——传输层把它写回同一连接。
- **替代**：新增独立的"审批连接管理器"维护 fd↔等待映射——传输层已支持 async handler 写回同连接，无需另造一层。否决（过度设计）。

### D2 · 用 `CheckedContinuation` 把"用户点按/超时"桥接回 async handler，单次 resume 守卫
async handler 需挂起直到用户点按或倒计时到点。
- **决策**：`PetController.requestDecision(for:) async -> BridgeResponse` 内用 `withCheckedContinuation`；卡牌按钮回调与倒计时各持一个 resume 入口，用一个"已完成"守卫（`MainActor` 上的单次置位）保证 continuation 只 resume 一次（防双 resume 崩溃/泄漏）。倒计时到点 resume `.defer`。
- **替代**：用 `AsyncStream` / actor 邮箱——单值一次性结果用 continuation 更直接。否决。

### D3 · CLI 决策类走阻塞读回传（复用 M3 `BridgeClient` 读取超时），通知类仍单向
- **决策**：`HookRuntime` 按 `content.needsResponse` 分流：`false` → M3 的单向 `send`（写完即 `exit 0`）；`true` → 阻塞 `send` 写请求后**阻塞读** `BridgeResponseEnvelope`，读取截止时间 = 用户响应 deadline（默认 20s，可配，须 < 工具 hook timeout）。收到 → `adapter.encodeResponse` → 写 stdout → `exit 0`；连接失败/读超时 → `defer`。
- **替代**：CLI 轮询文件/二次连接取结果——同一阻塞连接最简单且与 §3.4 一致。否决。

### D4 · fail-open 计时分层：CLI deadline 是兜底，App 倒计时是优化
两端都计时：CLI 读取截止（默认 20s）与 App 卡牌倒计时（同值）。
- **决策**：**CLI 端是 fail-open 的最终保证**——即便 App 崩溃/卡死/连接半开，CLI 到 deadline 必 `defer ≤` 截止（连接失败路径 ≤2s）。App 倒计时到点回 `.defer` 是"尽早释放工具"的优化路径。两者幂等：App 先回 `.defer`，CLI 收到即回退，等价于超时。配置 deadline 略小于 hook timeout、CLI 读超时略≥App 倒计时以避免赛跑误差。
- **替代**：只在 App 端计时——App 崩溃时 CLI 永久阻塞，违反 fail-open KPI。否决。

### D5 · `RiskClassifier` 与 `ActionPreview` 组装解耦，分级规则数据驱动放 Core
- **决策**：adapter 只负责把 `tool_input` 组装成 `ActionPreview`；`RiskClassifier` 是独立纯函数（输入工具名+命令字符串 → `RiskLevel`），规则以数据（模式表）驱动，便于逐条单测。气泡按 `risk` 取配色/默认焦点。分级在 adapter 解析时填入 `ApprovalContent.risk`（Core 内调用，不依赖 UI）。
- **替代**：把分级硬编进 adapter `switch`——不可配、难测。否决。

### D6 · `allowAlways` 先 spike（M4-3a）再 gate，主闭环不依赖
当前 Claude Code 版本是否支持持久/会话级 allow 规则未知。
- **决策**：先做 M4-3a——查官方文档/本机 hook fixture 验证 `allowAlways` 或等价机制可落地方式，产出最小 fixture + 单测。通过 → adapter 生成 `alwaysAllow`、`encodeResponse` 输出持久 allow、卡牌显示"始终允许"；不通过 → 记录不支持、`alwaysAllow` 恒 `nil`、卡牌隐藏该按钮。**deny/allowOnce/defer 主闭环（M4-1/M4-3/M4-4/M4-5/M4-6/M4-8）不把 `allowAlways` 作硬依赖**，可先行合入。
- **替代**：假定支持并实现——若机制不存在则返工且误导用户。否决。

### D7 · 队列堆叠（M4-7）与单气泡 demo（M4-8）解耦
- **决策**：`BubbleQueue` 以 `requestId` keyed 管理多请求，FIFO + 露头 + "还有 N 个待处理"，优先级 `decide`>`notify`>`greet`；每卡独立倒计时与超时出栈。M4-8 核心价值验收用**单气泡场景**即可，不阻塞于 M4-7；多气泡作为并发健壮性补充。
- **替代**：M4-8 必须等 M4-7——拖慢核心闭环验收。否决（按任务拆解建议）。

## Risks / Trade-offs

- **[多个并发审批 = 多个阻塞连接占线程]** → M3 已把连接读写迁出协作池、每连接独立处理；实际用户一次处理一个，并发度低；`BubbleQueue` 串行呈现但各连接独立 await，不互相饥饿（pet-controller 已加"不饿死其它连接"场景）。
- **[continuation 双 resume / 泄漏]** → `MainActor` 单次"已完成"守卫；按钮与倒计时共用一个完成入口；卡牌出栈即视为已完成。
- **[`requestId` 错配回错连接]** → handler 闭包捕获本连接的 continuation，`BridgeResponseEnvelope.requestId` 用请求的 `requestId` 回填；队列以 `requestId` 索引卡牌→结果。
- **[CLI 与 App 倒计时赛跑导致误判]** → D4 幂等设计 + deadline 分层（CLI 读超时 ≥ App 倒计时 ≥ 用户 deadline < hook timeout）。
- **[allowAlways 机制不存在]** → D6 spike gate，主闭环不依赖；隐藏按钮 + 记录结论。
- **[encodeResponse 回写字节/exit 语义错误导致工具放行错误操作]** → 字节级 + exit 语义单测（deny/allowOnce/defer 三路），这是安全关键路径。

## Migration Plan

纯新增 + 行为扩展，无数据/配置迁移。部署顺序按任务拆解关键路径：M4-1 → (M4-2 ∥ M4-3 ∥ M4-3a ∥ M4-5) → M4-4/M4-6 → M4-8，M4-7 可并行。回滚策略：M4 的改动局限在 `decide` 分支与决策类 CLI 路径，回退到 M3 即恢复纯通知态（通知链路不受影响）；`allowAlways` 分支独立，spike 失败时不合入即可。

## Open Questions

- `allowAlways` 的 `scopeHint` 粒度（按工具名 / 按命令前缀 / 按目录）——由 M4-3a spike 结论确定。
- 用户响应 deadline 默认值（暂定 20s）与各工具 hook timeout 的安全间距——以本机实测为准、可配。
- `decide` 在场时通知"小红点"的承载位置（宠物角标 vs 菜单栏）——M4-7 实现时定，先用宠物角标。
