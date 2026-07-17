# VibePet 从 open-vibe-island 选择性功能移植计划

- **状态：** Done（实现、全量验证、范围审计与双重评审完成）
- **制定日期：** 2026-07-15
- **接收项目：** VibePet
- **参考项目：** [Octane0411/open-vibe-island](https://github.com/Octane0411/open-vibe-island)
- **VibePet 基线：** `722989d3dc24ae5b490e5273651e66d46258db59`
- **本地参考基线：** `open-vibe-island@1e26dfc8d42bec0da7627986d49c2320b2593610`
- **执行分支：** `feat/open-vibe-island-selective-port`
- **执行日期：** 2026-07-16 至 2026-07-17

## 1. 决策摘要

VibePet 不重新 fork open-vibe-island，也不替换现有主干。后续以当前 VibePet 为产品事实来源，按功能和行为选择性移植上游的成熟实现、边界条件及测试案例。

本计划优先移植以下四类能力：

1. Hook 与 Unix socket Bridge 的 fail-open 和传输加固。
2. Session 生命周期幂等、晚到事件处理和单一状态所有权。
3. Claude Code / Codex 安装、卸载及健康检查的兼容性加固。
4. 终端跳回目标解析和精确匹配能力。

移植单位是“可验证行为”，不是文件。若 VibePet 已经具备某项行为并有充分测试，则记录为无需移植，不为追求代码一致而替换现有实现。

## 2. 背景与当前基线

当前 VibePet 已具备完整的 Claude Code + Codex 本地交互闭环：

```text
Claude Code / Codex hook
  → VibePetHooks
  → ToolAdapter / HookRuntime
  → NDJSON Unix socket
  → BridgeServerHost
  → AgentEvent / SessionState
  → Pet / Bubble / Dashboard
  → native approval or answer response
```

同时已经实现：

- 桌面宠物窗口和 spritesheet 动画；
- 审批、问题和通知气泡；
- 宠物导入、选择和持久化；
- Onboarding、设置、菜单栏和本地化；
- Hook 安装、卸载、修复、manifest 和稳定 helper 路径；
- Terminal jump-back 和活动进程发现；
- Core、App、Setup、E2E 四层测试。

制定本计划时，根项目 `swift test` 的基线结果为：

```text
Executed 446 tests, with 0 failures
```

该结果是所有移植阶段的最低回归门槛。任何阶段不得以“上游测试通过”代替 VibePet 自身测试。

## 3. 移植目标

### 3.1 产品目标

- 提升 Claude Code 与 Codex hook schema 变化时的兼容能力。
- 确保 malformed input、socket 失败、超时、断连和 App 未运行时始终 fail-open。
- 减少重复、晚到和乱序事件造成的重复气泡、状态复活或 session 闪烁。
- 保持安装、卸载和 repair 对用户原有配置非破坏、可诊断、可恢复。
- 提升终端跳回的精确性，避免跳错 tab、pane 或窗口。
- 降低 Bridge、Pet、Dashboard 之间多份 session 快照失步的风险。

### 3.2 工程目标

- 保持 `VibePetCore/` UI-independent。
- 保持 `VibePetHooks` 和 `VibePetSetup` 为薄 CLI。
- 保持本地优先，不增加网络、遥测、上传或远程 relay。
- 保持现有 public model、bridge wire format 和持久化数据的兼容性；需要变更时必须单独设计迁移。
- 每个移植行为先有失败测试或明确的差距证明，再修改实现。
- 每个阶段独立提交并可按依赖关系逆序回滚，不做一次性大迁移。

## 4. 不在移植范围内

以下 open-vibe-island 能力不纳入本计划：

- Claude Code、Codex 之外的 Agent adapter、hook 和 installer；
- notch/island overlay UI 及其窗口协调系统；
- Sparkle 自动更新；
- Apple Watch、iOS、HTTP/SSE 或其它网络 relay；
- telemetry、usage 上传、远程生成和账户系统；
- Accessibility、CGEvent、keystroke 或终端文本注入；
- Cursor、Gemini、Kimi、OpenCode、Warp 等范围外集成；
- 大范围 transcript discovery、usage tracking 和跨 Agent registry；
- 上游完整 `AppModel`、完整 `BridgeServer` 或各工具 `*InstallationManager` 的整体复制；
- 仅为与上游目录或命名一致而进行的重命名、搬文件和抽象重构；
- 对真实 `~/.claude`、`~/.codex` 执行安装冒烟测试。

现有 VibePet 已支持的 cmux、VS Code 等 jump fallback 不得因本计划回退，但本计划也不借机扩展新的终端或 IDE。

## 5. 移植原则与阶段门

每个候选功能必须按以下顺序执行：

1. **固定参考版本：** 在任务或 PR 中记录 VibePet commit 和 open-vibe-island commit。
2. **读取两侧实现：** 明确接收文件、上游来源文件、调用关系和相关测试。
3. **证明差距：** 新增失败测试，或记录当前实现已覆盖该行为而将任务关闭为 no-op。
4. **最小适配：** 移植算法、边界条件或测试案例，不复制范围外模型和 coordinator。
5. **定向验证：** 先运行对应测试 suite。
6. **完整验证：** 运行 `swift test`；所有预期 test target 必须被发现，0 failures、无意外 skip。`446 tests / 0 failures` 仅作为制定计划时的基线信息。
7. **范围审计：** 检查没有新增 Agent、网络、AX/keystroke、真实用户配置写入或 Core UI import。
8. **记录来源：** 在 PR 或 commit 中记录参考的上游文件、commit 和适配差异。

若现有测试已证明行为等价，不得为了“与上游同步”重写实现。

## 6. 优先级总览

| 优先级 | 工作流 | 目标 | 依赖 | 预估工作量 |
| --- | --- | --- | --- | ---: |
| P0 | A. Hook / Bridge 加固 | 保证所有传输失败有界且 fail-open | M0 | 2–4 工程日 |
| P0 | B1. Session reducer 语义 | 幂等、晚到事件和 lifecycle 规则确定化 | M0 | 3–5 工程日 |
| P1 | C. Installer 兼容性 | 非破坏合并、feature 所有权和健康漂移诊断 | M0 | 2–4 工程日 |
| P1 | A2. Adapter / CLI 兼容性 | 真实 schema fixture 与进程级 fail-open | M1 | 2–4 工程日 |
| P2 conditional | B2. Session 状态所有权 | 先审计 mutation owner；仅在发现真实失步风险时收敛 | B1 | 1–7 工程日 |
| P2 | D. Terminal jump 精确性 | 先审计捕获字段，再增强精确匹配和歧义保护 | M0 | 3–5 工程日 |
| Gate | E. 集成与发布门 | 全量回归、人工 QA、范围审计 | A–D | 2–3 工程日 |

以上是相对规划量级，不是交付承诺。若差距测试证明当前实现已覆盖候选行为，对应工作量应降为审计和记录，不应强行使用预算。

## 7. 目标架构

### 7.1 保持的 Core 边界

```text
VibePetCore
  ├─ Adapters: native payload ↔ AgentEvent / BridgeResponse
  ├─ Bridge: local NDJSON Unix socket transport
  ├─ Session: pure reducer and derived state
  ├─ Install: pure config mutation + controlled file writes
  └─ Pet / Persistence / Geometry: VibePet product domain
```

Core 不导入 AppKit 或 SwiftUI。系统命令、AppleScript、进程检查等副作用继续留在 App，或通过可注入 closure 暴露给 Core 逻辑。

### 7.2 Session 状态所有权的条件目标

M0 先列出所有 `SessionState` 实例、mutation site、发布路径和消费者。只读 value snapshot 或纯 projection 不自动等同于第二个 canonical owner。若审计确认当前只有 `BridgeServerHost` 修改 reducer，且不存在可复现的失步或漏发布，则 M3 可以关闭为 no-op，优先收窄写权限和补测试。

只有审计证明需要独立 Store 时，才采用以下目标：

```text
BridgeServerHost
  ├─ transport ingress
  ├─ adapter invocation
  └─ process / terminal I/O
           │
           ▼
@MainActor AppSessionStore
  ├─ canonical SessionState
  ├─ accept(event)
  ├─ reconcile(discovered, aliveIDs)
  └─ transition result
           │
     ┌─────┼──────────┐
     ▼     ▼          ▼
   Pet   Dashboard  StatusItem
```

- 无论是否新增 Store，App 运行期间只能有一个可写的 canonical `SessionState` owner。
- Pet、Dashboard 和 StatusItem 只消费只读状态或纯派生 projection。
- Decision continuation 和 FIFO queue 继续由现有交互层管理，不能放进状态 owner 并阻塞其它事件。
- 不为模仿上游 `AppModel` 而新增类型；行为测试能证明当前结构安全时保持现状。

## 8. 里程碑和任务拆解

## M0：建立差距矩阵与回归基线

### 目标

在不修改生产实现的前提下，确认每个候选行为当前是否已覆盖，避免重复移植。

### 任务

- [x] 记录执行时的 VibePet 和 open-vibe-island commit。
- [x] 运行 `swift test` 并保存测试总数、失败数及偶发 SIGPIPE 重跑结果。
- [x] 为每个工作流创建“已有 / 缺失 / 不适用”矩阵。
- [x] 确认所有新增 fixture 均脱敏且来自真实 payload 或上游测试事实；删除 Codex 占位 alias/能力假设。
- [x] 对用户可见 decision deadline 变化创建 OpenSpec change `harden-open-vibe-island-selective-port`。

### 初步审计结果（M0 启动状态）

以下结论来自计划制定时的源码和测试审阅，实施者仍需在固定 commit 上复核：

| 领域 | 已有行为 | 待证明或已识别缺口 |
| --- | --- | --- |
| Socket 基础 | SIGPIPE ignore、2 秒 connect timeout、client read timeout、socket `0600`、support directory 权限、self-pipe 唤醒 accept、stop/restart 测试 | frame 大小上限、server partial-read deadline、accepted handler 收尾、所有 unlink 的节点身份保护 |
| Hook CLI | notification one-way、decision blocking、skip 在读 stdin 前生效、debug 仅 stderr、最终 exit 0 | tool-specific timeout budget、client 提前断开后的 App pending decision 清理、更多进程级 E2E |
| Request 模型 | 当前是一连接一请求 | response `requestId` 尚需校验；不需要上游 multiplex client |
| Session 状态 | Core pure reducer、actionable guard、process-not-seen debounce、discovered/hook merge | duplicate/stale transition 和副作用幂等合同仍需系统测试 |
| Installer | 统一 HookInstaller、writer、manifest、health、stable helper | Codex feature ownership 的旧 manifest 兼容和更完整漂移矩阵 |
| Terminal | hook-time capture、iTerm/Terminal/Ghostty 及现有 cmux/VS Code 路径 | 先审计每种终端实际捕获字段，再判断 resolver/probe 缺口 |

M0 不得把这些“待证明”项目直接当作实现任务；若新增测试证明现有行为正确，应将追踪项标记为 `No-op`。

### 交付物

- 更新本文件第 13 节的追踪表；
- 每个实际缺口对应一个可独立实现的 task/issue；
- 无生产代码 diff。

### 验收

- 基线 `swift test` 通过；
- 没有把“上游存在”直接等同为“VibePet 缺失”；
- 所有 P0/P1 任务都有接收文件和验证测试位置。

---

## M1：Hook 与 Bridge 传输加固

### 目标

确保 partial frame、oversized frame、timeout、broken pipe、stale socket、并发和 shutdown 等场景不会让 Claude Code 或 Codex 阻塞、崩溃或收到错误响应。

### 上游来源

- `open-vibe-island/Sources/OpenIslandCore/BridgeTransport.swift`
- `open-vibe-island/Sources/OpenIslandCore/BridgeCommandClient.swift`（仅用于确认其 multiplex 模型不适用，不作为默认移植来源）
- `open-vibe-island/Sources/OpenIslandCore/BridgeServer.swift`
- `open-vibe-island/Sources/OpenIslandHooks/OpenIslandHooksCLI.swift`

### VibePet 接收位置

- `VibePetCore/Bridge/BridgeSocketIO.swift`
- `VibePetCore/Bridge/BridgeClient.swift`
- `VibePetCore/Bridge/BridgeServer.swift`
- `VibePetCore/Bridge/SocketPath.swift`
- `VibePetCore/Bridge/HookRuntime.swift`
- `VibePetCore/Bridge/HookInvocation.swift`
- `VibePetHooks/main.swift`

### 测试先行任务

#### M1.1 NDJSON framing 和资源上限

- [x] partial frame 分段到达后只解码一次。
- [x] 当前一连接一请求模型保持不变；单连接收到额外 frame 时安全关闭，不扩展为 multiplex transport。
- [x] EOF 时若已有一份完整、未超限 JSON，保持当前兼容行为并允许解码；截断或 malformed JSON 有界失败。
- [x] 引入显式 `maximumFrameBytes`（4 MiB）；精确边界、超限 1 byte 和多次小块追加均有测试。
- [x] 服务端 accepted connection 使用 monotonic absolute frame deadline：silent、partial 和持续滴流均从 accept 起约 2 秒退出。
- [x] notification 不等待 response；隔离 support path 的真实 CLI 进程测试小于 3 秒。
- [x] decision 使用按工具区分的 deadline，并满足 M1.1a 的跨层预算。

测试位置：

- `Tests/VibePetCoreTests/BridgeEnvelopeCodecTests.swift`
- `Tests/VibePetCoreTests/BridgeResponseCodecTests.swift`
- `Tests/VibePetCoreTests/BridgeTransportHardeningTests.swift`
- `Tests/VibePetCoreTests/BridgeRoundTripTests.swift`

#### M1.1a 跨层 timeout 和 pending decision 清理

当前 Claude 安装 timeout 为 86,400 秒，Codex PermissionRequest timeout 为 3,600 秒，而 Hook CLI 统一使用 Claude timeout。M1 必须改成 tool-specific budget，并满足：

```text
App decision deadline + response margin < CLI read deadline
connect timeout + CLI read deadline + process margin < tool hook timeout
```

初始预算为：

| 工具 | Tool hook timeout | Connect | CLI read | App decision |
| --- | ---: | ---: | ---: | ---: |
| Claude Code | 86,400s | 2s | 86,390s | 86,385s |
| Codex | 3,600s | 2s | 3,590s | 3,585s |

上述 App deadline 是新增的用户可见行为，实施前必须更新 OpenSpec。单元测试使用注入 clock 和缩短后的同比例 deadline，不真实等待。

必须覆盖：

- [x] App 在 deadline 前响应，CLI 正常输出一次。
- [x] App deadline 到期时清除 pending bubble、actionable state 和 continuation，并回复 defer。
- [x] CLI/tool 连接 EOF/HUP 后，server 在 2 秒内按 request ID 清除 pending bubble、actionable state 和 continuation。
- [x] 一连接一请求且 client 每次关闭 fd；迟到或额外 response 不会进入下一请求。
- [x] timeout 后用户迟到点击被忽略，不二次 resume、不残留 decision badge。
- [x] App/Bridge stop 显式 fail-open 所有 pending decisions；server handler 不无限等待。
- [x] 服务端解码 decision 后并行监视 accepted fd 的 EOF/HUP，并按 request ID 取消 request task 和 UI decision。

#### M1.2 stale socket、权限和 SIGPIPE

- [x] stale Unix socket 可以安全重建。
- [x] socket 路径上的普通文件或目录保持原样，server 启动返回安全错误。
- [x] 普通文件保护与真正失联 `S_IFSOCK` stale socket 清理分别测试。
- [x] 可删除节点必须是当前用户所有、位于权限受控 VibePet support directory 的 Unix socket。
- [x] bind 后记录 device/inode；所有 unlink 前重新 `lstat` 并校验 identity。
- [x] 运行期间替换 socket path 后，stop 保留替代文件。
- [x] support directory/socket 权限分别为 `0700`/`0600`。
- [x] peer 提前关闭时 client/server 以 write error fail-open，不触发 SIGPIPE 退出。
- [x] server stop/restart 清理 listen/wake/accepted fd，partial handler 有界退出。
- [x] 100 次 partial connection + stop/restart 后 handler 完成且 `/dev/fd` 不持续增长。

保护范围包括 `SocketPath.removeStaleSocket()` 和 `BridgeServerState.stop` 等所有删除 socket path 的路径，而不只处理启动前 stale socket。

#### M1.3 一连接一请求和 response 身份校验

当前 `BridgeClient.send` 每次创建新连接，server 每个 accepted connection 只读一帧、写一帧。因此不移植上游持久连接、multiplex pairing 或完整 `BridgeCommandClient`。

- [x] `BridgeClient` 校验 `BridgeResponseEnvelope.requestId == BridgeEnvelope.requestId`。
- [x] request ID 不匹配时返回 `invalidResponse`，HookRuntime fail-open。
- [x] duplicate/额外 frame 不产生第二次 stdout 或状态变化。
- [x] server stop 分别以 frame deadline 或显式 decision cancellation 收尾；App deadline 仅作存活连接后备。
- [x] 保持短连接协议，不引入 multiplex pairing abstraction。

#### M1.4 真实 Hook CLI fail-open

扩展 `Tests/E2E/`：

- [x] App 未运行；
- [x] socket missing/refused；
- [x] malformed stdin；
- [x] server disconnect；
- [x] timeout（生产长预算使用注入短 deadline，不真实等待）；
- [x] broken pipe；
- [x] `VIBEPET_SKIP_HOOKS=1`；
- [x] debug off 默认静默，debug on 仅写 stderr；
- [x] App/CLI/tool timeout 公式、常量接线与缩短边界场景；
- [x] decision peer EOF/HUP 后 2 秒内清理 pending UI/canonical state；
- [x] 持续滴流超过 accept 起 2 秒时 absolute frame deadline 仍终止 handler。

所有失败场景必须满足：在本节规定的 deadline 内结束、exit 0、stdout 为空、工具回到原生流程。

### M1 验收

- 正常 response 是且仅是一份工具原生 JSON，且 request ID 匹配；
- connect 最多 2 秒、server frame 从 accept 起最多 2 秒、notification 进程测试最多 3 秒；decision 按 M1.1a 的 tool-specific budget 有界结束；
- client EOF/HUP 后 2 秒内清理 request task、bubble、actionable state 和 continuation；App 长 deadline 只处理连接仍存活但用户不响应的情况；
- 无无限 buffer；100 次异常连接/stop 循环后所有 handler 完成，fd 数不持续增长；
- 普通文件/目录及被替换的 socket path 节点不被误删；
- 不改变当前一连接一请求 wire model；
- 定向测试和 `swift test` 全部通过。

---

## M2：Session reducer 幂等和生命周期规则

### 目标

定义 duplicate、late、stale 和 discovered/hook 合并的明确行为，确保 reducer 的真实 transition 可被 App 层安全消费。

### 上游来源

- `open-vibe-island/Sources/OpenIslandCore/AgentSession.swift`
- `open-vibe-island/Sources/OpenIslandCore/AgentEvent.swift`
- `open-vibe-island/Sources/OpenIslandCore/SessionState.swift`
- `open-vibe-island/Tests/OpenIslandCoreTests/SessionStateTests.swift`

### VibePet 接收位置

- `VibePetCore/Session/SessionModels.swift`
- `VibePetCore/Session/AgentEvent.swift`
- `VibePetCore/Session/SessionState.swift`
- `Tests/VibePetCoreTests/SessionStateTests.swift`

### 先确定的行为合同

- [x] 重复 `sessionStarted` 不产生第二个 session，不丢失更精确 jump target，也不将 waiting/completed 的较新状态降级。
- [x] 重复 permission/question/completion/resolution 是幂等 no-op。
- [x] 陈旧 activity 或 turn completion 不覆盖更新状态。
- [x] turn-level Stop 与真正 SessionEnd 分离；新 activity 仅恢复 turn-level completed，不能复活 ended session。
- [x] 晚到 jump target 仅补缺失字段，不覆盖已有精确 session ID 或 TTY。
- [x] 单次 process discovery 缺口不隐藏 session；连续确认缺失后才清理。
- [x] approval/question session 不因短暂漏检消失，只由 resolution/fail-open 退出 actionable state。
- [x] discovered placeholder 仅在唯一精确匹配时合并；歧义时保留两项。

### 实现约束

- 优先让 `SessionState.apply` 返回是否发生真实变化，或返回最小 transition 描述；不要先引入通用事件总线。
- 仅在测试证明需要时增加 per-session lifecycle watermark。
- 不使用全局墙钟顺序简单丢弃所有旧事件；SessionEnd 和 merge-only metadata 必须有明确例外。
- `AgentSession` 是 public `Codable` 类型。新增字段必须可选或提供向后兼容默认值，并增加旧数据 decode 测试。
- 不移植额外 Agent metadata、remote session、Codex.app 特例或完整 process monitoring coordinator。

### M2 验收

- 相同事件重放不会改变状态或重复副作用；
- stale/late 规则由测试固定；
- 现有 pet activity、attention count、running count 和 visible sessions 派生结果不回归；
- `swift test --filter SessionStateTests` 和完整测试通过。

---

## M3：Session 状态所有权审计与条件收敛

### 目标

先证明当前是否存在多个可写 owner、漏发布或 snapshot 失步，再决定是否新增 Store。只读 snapshot 本身不是重构理由。

### 上游参考

- `open-vibe-island/Sources/OpenIslandApp/AppModel.swift`

只参考“单一状态 owner + effects 外置”的设计，不复制其多 Agent、notch、updater、Watch 或 process coordinator。

### M3.0 所有权审计

- [x] 审计每个 `SessionState` 实例及创建位置。
- [x] 审计 mutation site、publish 调用和消费者。
- [x] 以完整 `SessionState` 相等测试锁定 Pet、Dashboard、StatusItem 同版发布。
- [x] 覆盖无状态变化的 liveness sweep、duplicate/stale event 和启动 reconciliation。
- [x] 确认 `BridgeServerHost` 是唯一 canonical writer；Pet 持有 private snapshot，Dashboard/Menu 为只读 projection。
- [x] Greeting 的可复现两阶段快照差异已在现有 publish path 修复；未发现第二个 owner，因此不执行 M3.1。

M3.0 结论：`No-op`（不新增 Store）。审计发现的 Greeting 发布顺序缺口已用最小现有路径修复；以下 M3.1 条件任务不适用。

### M3.1 条件实现：窄 AppSessionStore

仅在 M3.0 证明需要时：

- **No-op：** 不新增 `VibePetApp/Session/AppSessionStore.swift`。
- **No-op：** 不创建第二个 canonical owner 或 Store API。
- **保留：** `BridgeServerHost` 继续持有唯一 canonical `SessionState` 并负责 effects。
- **保留：** Dashboard、Pet、StatusItem 消费相同 snapshot/纯 projection；selection 仍为局部 UI 状态。
- **保留：** BubbleQueue、request ID、single-resume、M1.1a deadline 和 stop fail-open 清理。

建议测试位置：

- 可选新增 `Tests/VibePetAppTests/AppSessionStoreTests.swift`；
- 若现有测试无法覆盖 host 边界，可新增 `Tests/VibePetAppTests/BridgeServerHostTests.swift`；
- 更新 `SessionDashboardProjectionTests.swift`、`StatusItemControllerTests.swift` 及相关 Pet/flow 测试。

### M3 验收

- 审计证明 App 运行期间只有一个 canonical mutation owner；是否新增 Store 由证据决定。
- 相同 transition 同步驱动 Pet、Dashboard 和 StatusItem，或现有 push 路径有确定性一致性测试。
- decision continuation 恰好 resume 一次，等待用户时不会阻塞其它 session event。
- Dashboard 打开、关闭和 selection 不改变 canonical session state。
- 无状态变化的 sweep 不产生无意义发布。
- 所有 App、Core 和 E2E 测试通过。

---

## M4：Claude Code / Codex Adapter 和 CLI 兼容性

### 目标

选择性吸收上游已验证的 native hook schema alias、response encoding 和边界案例，不猜测工具能力。

### 上游来源

- `open-vibe-island/Sources/OpenIslandCore/ClaudeHooks.swift`
- `open-vibe-island/Sources/OpenIslandCore/CodexHooks.swift`
- `open-vibe-island/Sources/OpenIslandHooks/OpenIslandHooksCLI.swift`
- 对应 `open-vibe-island/Tests/OpenIslandCoreTests/ClaudeHooksTests.swift`
- 对应 `open-vibe-island/Tests/OpenIslandCoreTests/CodexHooksTests.swift`

### VibePet 接收位置

- `VibePetCore/Adapters/ClaudeCodeAdapter.swift`
- `VibePetCore/Adapters/CodexAdapter.swift`
- `VibePetCore/Bridge/HookRuntime.swift`
- `VibePetHooks/main.swift`
- `Tests/Fixtures/claude/`
- `Tests/Fixtures/codex/`
- Adapter 与 E2E 测试文件

### Claude Code 任务

- [x] malformed、unknown、missing fields 保持 nil/defer。
- [x] PermissionRequest allow once、session-scoped always allow、deny 的原生 JSON 精确测试。
- [x] AskUserQuestion 单选、多选、自由输入和空回答测试。
- [x] UI-only “其他”选项不回写原生问题定义。
- [x] Stop 摘要保持 inline → bounded local transcript → fallback 的顺序。
- [x] transcript 仅限本地 regular file、4 MiB、末尾 2,000 行；异常输入有界失败且无网络。

### Codex 任务

- [x] PermissionRequest shell/apply_patch/MCP、Stop、notify 和 unknown/malformed fixture。
- [x] allow/deny 原生 JSON 精确测试。
- [x] question/defer 保持空 stdout；没有 fixture 证明的 terminal-required 能力不实现。
- [x] hook `session_id` 与 notify `thread-id` 来自真实 fixture；移除 `thread_id`/`turn-id` session fallback。
- [x] 未经验证的 free-form answer、Claude-only `AskUserQuestion` 特例和 persistent allow 不实现。
- [x] 不假设多个 matching hooks 中 VibePet 拥有独占决策权。

### M4 验收

- stdout 仍是严格协议通道，日志只能写 stderr；
- unknown/malformed payload 不 crash、不 hang；
- 没有虚构 Claude/Codex 能力；
- 所有新增字段均有脱敏 fixture；
- Adapter 定向测试、E2E 和完整测试通过。

---

## M5：Installer、Health 和 Binary Locator 加固

### 目标

保持现有统一 `HookInstaller + ToolConfigWriter + InstallManifestStore` 架构，选择性吸收上游纯配置 mutation、feature ownership 和漂移检测案例。

### 上游来源

- `open-vibe-island/Sources/OpenIslandCore/ClaudeHookInstaller.swift`
- `open-vibe-island/Sources/OpenIslandCore/ClaudeHookInstallationManager.swift`
- `open-vibe-island/Sources/OpenIslandCore/CodexHookInstaller.swift`
- `open-vibe-island/Sources/OpenIslandCore/CodexHookInstallationManager.swift`
- `open-vibe-island/Sources/OpenIslandCore/HookHealthCheck.swift`
- `open-vibe-island/Sources/OpenIslandCore/HooksBinaryLocator.swift`

`*InstallationManager` 只作为行为参考，不移植其类型和第二套 manifest。

### VibePet 接收位置

- `VibePetCore/Install/ClaudeCodeConfigWriter.swift`
- `VibePetCore/Install/CodexConfigWriter.swift`
- `VibePetCore/Install/HookInstaller.swift`
- `VibePetCore/Install/HookHealthCheck.swift`
- `VibePetCore/Install/HooksBinaryLocator.swift`
- `VibePetCore/Install/InstallManifest.swift`
- `Tests/VibePetSetupTests/`

### 任务

#### M5.1 Codex feature key 和所有权

- [x] 识别 current、legacy、mixed 和用户自有 hooks 场景。
- [x] install 保留用户已有合法 key，不无故切换。
- [x] manifest 记录 install 前 feature ownership receipt。
- [x] uninstall 仅在 receipt 证明 VibePet 启用且没有其它 hooks 时撤销 feature。
- [x] conservative full-file TOML preflight 拒绝不确定结构，原字节不被空模板覆盖。
- [x] 不实际启动 Codex；全部使用临时 URL 和固定 fixture。
- [x] 旧 manifest 缺字段时保守 decode 为 `unknown`。
- [x] `unknown` 时 uninstall 保留 feature；只有显式 repair 刷新为当前保守 ownership。

#### M5.2 Health 漂移矩阵

覆盖：

- [x] config 有 managed command、manifest 缺失；
- [x] manifest 标记 installed、managed entry 缺失；
- [x] command 指向旧 bundle/source 而非稳定 helper；
- [x] stable binary 缺失、不可执行或版本不符；
- [x] Codex feature disabled、错误 key 或仍有其它 hooks；
- [x] malformed Claude/Codex 配置及 malformed manifest。

Health check 必须只读，不得创建目录、修复或覆盖文件；repair 仍显式经过 `HookInstaller.repair`。

#### M5.3 Binary locator

- [x] 候选优先级明确：显式 override → app bundle/helper → executable 同级/SwiftPM product。
- [x] 候选必须是普通文件且可执行，managed destination 不得作为 source。
- [x] 显式 override 无效时 Setup/App 返回明确错误，不静默 fallback。
- [x] not-found 结果记录尝试过的候选；source 等于 destination 时删除前失败。

### M5 测试安全红线

- 所有 writer/installer 测试显式使用唯一临时 URL；
- 测试不得调用任何使用默认用户路径的 initializer 或 Setup CLI；安全边界在构造时成立，不能只依赖 teardown；
- 优先使用 RAII 临时目录 helper，并在正常 teardown 再次清理；
- 不依赖 `$HOME` override 伪装真实 home；
- 不运行 `swift run VibePetSetup install ...` 或 uninstall smoke test；
- 不读取或写入真实 `~/.claude`、`~/.codex`。

### M5 验收

- 重复 install 幂等；
- uninstall 只删除 VibePet-managed entries；
- 用户 hooks、未知 keys 和无关设置得到保留；
- 稳定 helper 路径继续正确单引号转义；
- malformed config 不被覆盖；
- Setup 定向测试和完整测试通过。

---

## M6：Terminal jump 精确性

### 目标

适配上游已验证的精确 identifier/TTY 匹配和歧义保护，不引入按键注入、范围外终端或阻塞 hook 的自动化。

### 上游来源

- `open-vibe-island/Sources/OpenIslandApp/ForegroundTerminalSessionProbe.swift`
- `open-vibe-island/Sources/OpenIslandApp/TerminalJumpTargetResolver.swift`
- `open-vibe-island/Sources/OpenIslandApp/TerminalJumpService.swift`
- 对应 `open-vibe-island/Tests/OpenIslandAppTests/` 测试

### VibePet 接收位置

- 可选新增 `VibePetApp/Bridge/ForegroundTerminalSessionProbe.swift`
- `VibePetApp/Bridge/TerminalJumpTargetResolver.swift`
- `VibePetApp/Bridge/TerminalJumpService.swift`
- `VibePetApp/Bridge/BridgeServerHost.swift`，仅在接线必要时修改
- `VibePetCore/Adapters/TerminalJumpCapture.swift`，仅在真实捕获缺口时修改
- `Tests/VibePetAppTests/TerminalJumpTargetResolverTests.swift`
- `Tests/VibePetAppTests/TerminalJumpServiceTests.swift`
- 可选新增 `Tests/VibePetAppTests/ForegroundTerminalSessionProbeTests.swift`
- `Tests/VibePetCoreTests/TerminalJumpCaptureTests.swift`

### 匹配优先级

- **iTerm：** session ID → TTY → 唯一安全 fallback。
- **Apple Terminal：** TTY → tab/custom title → 唯一安全 fallback。
- **Ghostty：** terminal/session identifier → cwd/title 唯一候选。
- **现有 cmux / VS Code：** 保持当前行为，不从上游扩大支持面。

cwd/title 等弱信号只允许在唯一候选时使用。多候选或脚本失败时不得任意选择；应保留原 target 或使用安全的 app/cwd fallback。

### 任务

#### M6.0 捕获字段与传递链审计

在增强 resolver 前，先用脱敏 env/payload fixture 为每个已支持终端列出实际可获得字段：terminal app、session/terminal ID、TTY、cwd、title。验证字段从 `TerminalJumpCapture` 经 `SourceInfo`、bridge 和 `AgentSession` 到达 resolver。

- [x] iTerm 仅使用可归因 locator session ID / process TTY；
- [x] Apple Terminal 使用可归因 TTY / title；
- [x] Ghostty hook-time 仅记录 process TTY/cwd，不拼接无关 frontmost ID；
- [x] cmux / VS Code 现有字段和 fallback 不回归；
- [x] 缺少稳定 identifier 时，仅使用双向唯一弱信号或安全 fallback。

#### M6.1 Resolver gap test
- [x] iTerm session ID 和 TTY snapshot 校正保持原行为。
- [x] Ghostty/Terminal 精确 identifier/TTY 优先。
- [x] cwd path 标准化但不做模糊包含。
- [x] 多候选歧义时不修改 target。
- [x] snapshot/AppleScript 失败时保留原 target。
- [x] 模糊 target 不覆盖已有精确字段。

#### M6.2 可选 foreground probe

只有在产品行为需要“避免重复 activate”或“判断目标是否已前台”时才新增：

**状态：Deferred。** 当前没有该产品需求；新增 probe 只会增加 AppleScript/前台状态耦合，不进入本轮实现。

- **Deferred：** Ghostty focused terminal identifier probe；
- **Deferred：** Terminal normalized TTY foreground probe；
- **Deferred：** iTerm session ID/TTY foreground probe；
- **Deferred：** unknown/权限/脚本失败 probe 合同；
- **约束保留：** 任何未来 probe 都不得进入 hook blocking response 必经路径。

#### M6.3 Jump service gap-only 增强

- [x] identifier/TTY 精确命中优先；
- [x] AppleScript escaping 和空值处理有测试；
- [x] 目标消失时安全 fallback；
- [x] runner error fail-open，不影响 Hook/native flow；
- [x] 不发送文本、按键或命令到终端。

### M6 验收

- 只对 M6.0 证明可捕获的字段承诺精确匹配；
- 多候选不误跳，缺少稳定 identifier 时使用唯一弱信号或安全 fallback；
- 所有 AppleScript/process runner 可注入；
- 单测不调用真实终端或 osascript；
- terminal 自动化失败不影响 Bridge/Hook fail-open；
- 不新增 AX、CGEvent、keystroke 或范围外终端依赖；
- Terminal 定向测试和完整测试通过。

---

## M7：集成、人工验收和发布门

### 自动验证

按变更范围运行定向测试，最终必须运行：

```bash
swift test
```

建议的定向命令：

```bash
swift test --filter BridgeTransportHardeningTests
swift test --filter BridgeRoundTripTests
swift test --filter HookRuntimeTests
swift test --filter SessionStateTests
swift test --filter AppSessionStoreTests
swift test --filter ClaudeCodeAdapter
swift test --filter CodexAdapter
swift test --filter HookInstallerTests
swift test --filter HookHealthCheckTests
swift test --filter HooksBinaryLocatorTests
swift test --filter TerminalJumpCaptureTests
swift test --filter TerminalJumpTargetResolverTests
swift test --filter TerminalJumpServiceTests
```
如果新增测试类尚不存在，应先创建对应测试，再使用过滤命令。`446 tests / 0 failures` 是制定计划时的基线信息，不是按数量硬编码的完成条件；硬门槛是所有预期 test target 被发现、0 failures、无意外 skip。完整测试出现项目指南中已知的偶发 SIGPIPE 时，重跑完整测试或相关 filter，并同时记录首次和重跑结果；不得用“已知偶发”忽略稳定复现的 SIGPIPE。

最终自动验证（2026-07-17）：

- `swift build`：exit 0。
- `swift test --skip-build -q`：执行 592 tests，0 failures、0 unexpected、0 skip，exit 0，未出现 SIGPIPE；耗时约 30.6 秒。
- OpenSpec：`openspec validate harden-open-vibe-island-selective-port --strict` 通过。
- 静态范围审计与 `git diff --check` 通过。
- 最终规范合规评审与两路交叉代码质量评审均 PASS；出站 write deadline/4 MiB socket 可达性、connect flags、SessionEnd 竞态、generation-safe liveness、JSON health/mutation 同构、精确命令所有权和 Setup selector 等 blocking findings 已全部通过回归关闭。

### 验收 QA

本轮以隔离 support path、临时 socket 和注入 runner 做确定性验收，不通过测试脚本安装真实配置：

- [x] 真实 Hook CLI 子进程在 App 未运行时让 Claude Code/Codex 维持原生流程。
- [x] approval、question、notification 的 Bridge/Hook E2E 各完成一次。
- [x] approval 等待期间另一 session 的 activity 可继续更新。
- [x] Dashboard、Pet 和菜单栏从同一 canonical snapshot 派生。
- **Deferred / Not applicable：** 不驱动本机真实 iTerm/Terminal/Ghostty；输入 target、snapshot、匹配/fallback 由注入 runner 的确定性单测覆盖。
- [x] cmux/VS Code 现有路径没有回归。
- [x] 安装状态只通过临时目录 unit tests 和只读 health/status 验证；未执行真实 install/uninstall。

### 范围审计

- [x] `VibePetCore/` 未新增 AppKit/SwiftUI import。
- [x] 未新增 URLSession、HTTP listener、telemetry 或上传代码。
- [x] 未新增 Claude Code/Codex 之外的 Agent。
- [x] 未新增 AX、CGEvent、keystroke 或文本注入。
- [x] 未新增 Sparkle、MarkdownUI 或其它依赖。
- [x] 每项实现都能追溯到失败测试或已记录的差距。
- [x] VibePet `722989d3` 与上游 `1e26dfc` 来源及适配说明已记录。

## 9. 依赖关系和推荐执行顺序

```text
M0 基线与差距审计
 ├─→ M1 Hook / Bridge 加固 ─→ M4 Adapter / CLI 兼容
 ├─→ M2 Session reducer ────→ M3 ownership audit ──→ conditional Store
 ├─→ M5 Installer 加固
 └─→ M6 Terminal capture audit ─→ resolver/jump

M1 + M3 audit + M4 + M5 + M6
 └─→ M7 集成与发布门
```

推荐顺序：

1. 先做 M0。
2. 优先完成 M1 和 M2 两个 P0 风险面。
3. M2 稳定后执行 M3.0 所有权审计；只有证据证明需要时才新增 AppSessionStore。
4. M5 可以与 M2/M3 独立实施，但同一工作树保持单一 writer。
5. M6 只在核心 fail-open 和 lifecycle 稳定后接入。
6. M4 应在 Bridge 边界稳定后完成最终 E2E。
7. 最后执行 M7，不把多个未验证里程碑一次性合并。

## 10. 风险与缓解

| 风险 | 影响 | 缓解措施 |
| --- | --- | --- |
| 把上游模型整体复制进来 | 引入多 Agent、Watch、notch 等耦合 | 只移植行为和最小算法；PR 记录明确拒绝项 |
| Claude/Codex schema 猜测 | 输出无效 JSON，工具阻塞或错误授权 | 仅接受真实脱敏 fixture、上游测试或官方事实 |
| stdout 被日志污染 | Hook 协议失效 | 默认静默；debug 只写 stderr；进程级 E2E |
| App/CLI/tool timeout 顺序或 peer cancellation 错误 | 原生工具已继续但 App 留下孤儿审批 | tool-specific budget；monotonic deadline；EOF/HUP 后 2 秒内 request-scoped cancellation |
| stale socket 误删普通文件 | 用户数据破坏 | 文件类型和所有权保护测试；不盲目 unlink |
| event timestamp 不可靠 | 状态被错误丢弃或复活 | per-session 规则；SessionEnd/metadata 明确例外；测试 tie case |
| Store 持有 decision continuation | 一个审批阻塞所有 session | Store 只归约状态；continuation 留在交互层 |
| 新 Codable 字段破坏旧数据 | 配置或 bridge decode 失败 | optional/default + 旧数据 decode 测试 |
| 安装器双状态源 | status、repair 和 uninstall 互相冲突 | 保留现有统一 manifest，不移植 per-tool manager |
| TOML mutation 丢注释或未知设置 | 用户配置损坏 | 保守行级 mutation；不确定时停止写入 |
| 测试写入真实 home | 污染开发者 Claude/Codex 配置 | 显式 temp URL；禁止 setup smoke test |
| terminal 弱信号误匹配 | 跳到错误会话 | identifier/TTY 优先；弱信号仅唯一候选 |
| 上游后续变化 | 计划基线漂移 | 每个里程碑重新固定 upstream commit 并审计差异 |
| 一次性大合并 | 难回滚、难定位回归 | 每个里程碑独立 PR/commit 和完整测试 |

## 11. 停止条件与升级决策

出现以下任一情况时，停止当前移植任务并要求产品或架构决策：

- 需要支持 Claude Code/Codex 之外的新 Agent；
- 需要网络、remote relay、telemetry、Sparkle、Watch 或移动端；
- 需要 Accessibility、keystroke、文本注入或新的系统权限；
- native schema 没有真实 fixture、上游测试或官方证据；
- 配置 mutation 无法保守地保留未知用户配置；
- 必须破坏 bridge wire format 或 public Codable model 且没有迁移方案；
- 无法为候选行为构造确定性测试；
- 单个候选需要复制上游大部分 coordinator 或引入第二个状态源；
- 预计改动扩大到本里程碑之外两个以上子系统；
- fail-open 红线无法在测试中证明。

若未来产品方向改为多 Agent 桌面控制中心，并且需要上游大多数 session discovery、process attachment、usage 和 terminal 平台能力，应另行重新评估 fork，而不是扩张本计划。

## 12. 完成定义

第一轮选择性移植在满足以下条件时完成：

- P0 的 M1、M2 全部完成或经差距审计关闭为 no-op；
- P1 的 M4、M5 完成，或有书面理由延期；
- M3 完成所有权审计；只有审计证明需要时才实现 Store，否则以 no-op 证据关闭；
- M6 只实施经产品确认且有捕获字段/差距测试的部分；
- M7 自动测试、人工 QA 和范围审计完成；
- 所有预期 test target 被发现，0 failures、无意外 skip；
- Hook fail-open、installer 非破坏性和 local-first 边界无回归；
- 文档追踪表、OpenSpec 和上游来源记录同步更新；
- 没有多个可写 canonical state owner、临时 compatibility shim 或未解释的范围外代码。

## 13. 执行追踪表

| ID | 工作项 | 优先级 | 状态 | 上游基线 | 验收证据 |
| --- | --- | --- | --- | --- | --- |
| M0 | 差距矩阵与测试基线 | P0 | Done | `1e26dfc` | 固定 `722989d3`/`1e26dfc`；基线 `522 tests` 暴露 2 个 socket-path 测试问题后修复 |
| M1.1 | NDJSON framing / bounded read / timeout budget | P0 | Done | `1e26dfc` | 4 MiB socket chunk read、outbound write deadline、EOF/silent/drip/100-cycle FD tests；tool-specific budget 公式 |
| M1.2 | safe unlink / stale socket / permissions / SIGPIPE | P0 | Done | `1e26dfc` | type/uid/device/inode、replacement、`0700/0600`、EPIPE tests |
| M1.3 | response request ID / handler 收尾 | P0 | Done | `1e26dfc` | mismatch fail-open、extra frame/EOF cancellation；保持短连接不移植 multiplex |
| M1.4 | Hook CLI fail-open E2E | P0 | Done | `1e26dfc` | `M1HookCLIFailOpenTests`：两工具 missing app、malformed、disconnect、skip、debug stderr |
| M2 | Session reducer lifecycle rules | P0 | Done | `1e26dfc` | duplicate/stale/end/liveness/merge；ended tombstone 与 provider-await 竞态回归 |
| M3 | Session ownership audit / conditional Store | P2 conditional | No-op | `1e26dfc` | Host 唯一 writer；修复 Greeting 同版发布；`M3SessionOwnershipTests`，不新增 Store |
| M4 | Claude/Codex schema 与 CLI 兼容 | P1 | Done | `1e26dfc` | bounded transcript、native JSON、synthetic option strip、fixture-only Codex identity/capability |
| M5.1 | Codex feature key 和所有权 | P1 | Done | `1e26dfc` | modern/legacy/mixed、legacy manifest、explicit repair、malformed config/manifest tests |
| M5.2 | Health 漂移矩阵 | P1 | Done | `1e26dfc` | binary/config/manifest drift、JSON structure preflight + before/after filesystem read-only snapshot |
| M5.3 | Binary locator 优先级与诊断 | P1 | Done | `1e26dfc` | authoritative override、candidate order、managed destination exclusion、self-copy guard |
| M6.0 | Terminal capture 字段与传递链审计 | P2 | Done | `1e26dfc` | attributable iTerm/Terminal facts；Ghostty 不拼接 frontmost ID；cmux/VS Code preserved |
| M6.1 | Terminal resolver 精确匹配 | P2 | Done | `1e26dfc` | ID/TTY priority、bidirectional unique cwd/title、ambiguity/failure preservation |
| M6.2 | Foreground terminal probe | P2 conditional | Deferred | `1e26dfc` | 当前无前台判断产品需求，不增加 hook/AppleScript 耦合 |
| M7 | 集成、验收 QA 和范围审计 | Gate | Done | `722989d3` / `1e26dfc` | build exit 0；592 tests / 0 failures / 0 skip；OpenSpec strict、范围审计、规范与代码质量评审 PASS |

状态只能使用：`Not started`、`Auditing`、`No-op`、`In progress`、`Blocked`、`Done`、`Deferred`。每次完成任务时更新上游基线和验收证据，避免计划与实现脱节。
