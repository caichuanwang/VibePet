# VibePet 技术实现方案

> 版本：v0.1（MVP）
> 日期：2026-06-17
> 配套文档：[《VibePet PRD》](./VibePet-PRD.md)
> 平台：macOS 14+ · Swift 6.x · SwiftUI + AppKit · 纯原生（非 Electron）

---

## 1. 总体架构（方案 A）

单一 Swift Package，四个 target，职责单一、可独立测试。hook 进程与宿主 App 通过 **Unix domain socket** 通信。

```
┌──────────────────────────────────────────────────────────────┐
│                        AI 编码工具                              │
│   Claude Code (settings.json)        Codex (config.toml)       │
│     PreToolUse / Notification / Stop   PermissionRequest /notify│
└───────────────┬───────────────────────────┬──────────────────┘
                │ 调用 hook 命令（事件 JSON 经 stdin）           │
                ▼                                               ▼
        ┌───────────────────────────────────────────────┐
        │   VibePetHooks (CLI 二进制)                     │
        │   - 解析工具事件 → 归一化 BridgeEnvelope        │
        │   - 连接 Unix socket 发送                       │
        │   - 决策类事件：阻塞等待回传（带超时 fail-open） │
        │   - 按工具格式把决策写回 stdout, exit 0         │
        └───────────────┬───────────────────────────────┘
                        │ Unix domain socket
                        │ ~/Library/Application Support/VibePet/bridge.sock
                        ▼
        ┌───────────────────────────────────────────────┐
        │   VibePetApp (SwiftUI 宿主)                     │
        │   ┌─────────────────────────────────────────┐  │
        │   │ BridgeServer (VibePetCore)               │  │
        │   │  监听 socket → 解码 → 路由               │  │
        │   └───────────────┬─────────────────────────┘  │
        │                   ▼                            │
        │   ┌─────────────────────────────────────────┐  │
        │   │ PetController                            │  │
        │   │  状态机：idle/greet/notify/decide        │  │
        │   └───────────────┬─────────────────────────┘  │
        │        ┌──────────┴──────────┐                 │
        │        ▼                     ▼                 │
        │  PetWindow(浮动宠物)   MenuBar / Settings       │
        │  + SpeechBubble(允许/拒绝)                      │
        └───────────────────────────────────────────────┘

   ┌───────────────────────────────────────────────┐
   │   VibePetSetup (CLI)                           │
   │   幂等写入/移除 Claude Code & Codex hook 配置  │
   └───────────────────────────────────────────────┘
```

### 1.1 Target 划分

| Target | 类型 | 职责 |
|---|---|---|
| `VibePetCore` | library | 数据模型、`BridgeServer`/`BridgeClient`、`BridgeEnvelope` 协议、生成管线、`ToolAdapter` 协议、持久化、配置。**不依赖 UI**，可被其它 target 复用与单测。 |
| `VibePetApp` | executable (app bundle) | SwiftUI 宿主：浮动宠物窗、菜单栏、设置页、导入照片、调用生成管线、运行 `BridgeServer`、弹气泡。 |
| `VibePetHooks` | executable (CLI) | 体积极小、启动极快的命令行二进制。被各工具 hook 调用，转发事件、决策类阻塞等待、按工具格式输出。 |
| `VibePetSetup` | executable (CLI) | 安装/卸载 hooks：把 `VibePetHooks` 拷贝到稳定路径（见 §1.2）、幂等写入工具配置、备份、精确移除。 |

> 为什么 hook 用独立 CLI 而非脚本：真二进制启动快、无解释器依赖、可复用 `VibePetCore` 的 envelope/socket 代码、阻塞等待逻辑可靠。

### 1.2 二进制分发与稳定路径（关键）

工具配置里注册的 hook command **不指向 `.app` 包内路径**，而指向一个与 app 位置解耦的稳定路径。安装时由 `VibePetSetup` 把 `VibePetHooks` 二进制**拷贝**到：

```
~/Library/Application Support/VibePet/bin/VibePetHooks
```

然后 `~/.claude/settings.json` / Codex `config.toml` 里的 command 指向这个拷贝路径。

**为什么这么做**（参考 open-vibe-island 的做法）：`.app` 一旦改名、移动目录或重装，包内绝对路径就失效，已注册的 hooks 会全部断掉。拷贝到固定的 Application Support 路径后，hook 路径与 app 的安放位置无关，重命名/移动 app 不影响已注册的 hooks。

- 安装流程：`VibePetSetup install` 或 App 设置页按钮 → ① 拷贝最新 `VibePetHooks` 到上述 `bin/` 路径（覆盖旧版，保证版本一致）→ ② 幂等写入工具配置指向该路径 → ③ 写入前备份原配置 → ④ 更新 manifest（见 §4.3）。
- 升级：每次安装/启动校验 `bin/VibePetHooks` 版本，落后则重新拷贝；配置无需改动（路径不变）。
- 卸载：`VibePetSetup uninstall` → 据 manifest 精确移除工具配置中 VibePet 写入的条目 + 删除 `bin/VibePetHooks` + 清理 manifest。

> `.app` 包内仍会内置一份 `VibePetHooks`（作为拷贝源），但工具**永远不直接引用包内路径**，只引用 `bin/` 下的拷贝。

---

## 2. 可插拔生成管线（Generation Pipeline）

核心抽象：把"照片 → 宠物素材"封装成协议，MVP 仅实现本地抠图，风格化/3D 后续以新实现接入，**上层不感知**。

```swift
// VibePetCore/Generation/PetGenerator.swift
public protocol PetGenerator: Sendable {
    /// 唯一标识，用于配置选择，如 "local-cutout" / "cloud-stylize" / "tripo-3d"
    var identifier: String { get }
    /// 由一张输入图片生成宠物素材
    func generate(from image: CGImage,
                  progress: @escaping (Double) -> Void) async throws -> PetAsset
}

public struct PetAsset: Codable, Sendable {
    public let id: UUID
    public let kind: PetKind            // .sprite2D（MVP）/ .stylized2D / .model3D（预留）
    public let primaryImageURL: URL     // 带透明通道的主精灵图（PNG/HEIC）
    public let layers: [PetLayer]       // 可选：分层素材，供动画使用（眼睛/身体等）
    public let boundingInset: EdgeInsets// 主体在画布中的边距，用于裁切/对齐
    public let metadata: [String: String]
}

public enum PetKind: String, Codable, Sendable { case sprite2D, stylized2D, model3D }
```

### 2.1 MVP 实现：`LocalCutoutGenerator`

```swift
// VibePetCore/Generation/LocalCutoutGenerator.swift
public struct LocalCutoutGenerator: PetGenerator {
    public let identifier = "local-cutout"

    public func generate(from image: CGImage,
                         progress: @escaping (Double) -> Void) async throws -> PetAsset {
        // 1. Vision 前景实例蒙版（macOS 14+）
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first else { throw GenError.noSubject }

        // 2. MVP：多主体时取面积最大的单个实例（多主体点选/合成排入后续版本）
        guard let instance = result.largestInstance(in: handler) else { throw GenError.noSubject }
        let masked = try result.generateMaskedImage(
            ofInstances: [instance], from: handler, croppedToInstancesExtent: true)

        // 3. 后处理：裁切空白、归一化尺寸、输出 PNG（保留透明）
        let url = try PetAssetStore.writeSprite(masked, id: ...)

        return PetAsset(kind: .sprite2D, primaryImageURL: url, layers: [], ...)
    }
}
```

要点：
- 全程本地，跑在 Neural Engine；不联网。
- `croppedToInstancesExtent` 直接裁到主体范围，省去手工 trim。
- **多主体**：Vision 可能返回多个前景实例；MVP 取面积最大者（`largestInstance` 按各实例蒙版像素数/外接框面积排序），多主体点选与合成排入后续版本。
- 失败语义：无显著主体 → `GenError.noSubject`，UI 提示换图/重试。
- **待机动画不依赖 AI**：用 Core Animation 对单张精灵做 squash/stretch（呼吸）、周期性轻微旋转/位移（晃动）、可选眨眼为叠加层（若 `layers` 提供，否则跳过）。

### 2.2 预留实现（不在 MVP 编码，仅定义占位）
- `CloudStylizeGenerator`（v1.1）：调用云端 img2img，把抠图转萌系/卡通；需 `APIKeyProvider` 与显式开关。
- `ThreeDGenerator`（v2.0）：TripoSR/Hunyuan3D 产出网格 → `model3D`，由 SceneKit/RealityKit 渲染。

### 2.3 管线选择
`GenerationService` 依据配置 `activeGeneratorID` 从注册表取 `PetGenerator`，对外只暴露 `generate(from:)`。新增生成器 = 注册一个实现，零侵入。

---

## 3. Bridge 协议（hook ↔ App）

### 3.1 传输
- **Unix domain socket**，路径 `~/Library/Application Support/VibePet/bridge.sock`。
- 目录权限 `0700`，套接字 `0600`，仅当前用户。
- 行分隔 JSON（newline-delimited JSON）；每条消息一行，便于流式读取。

### 3.2 消息信封（归一化）

> **设计与版权说明**：以下模型借鉴 open-vibe-island「规范事件 + 数据驱动渲染」的**思路/模式**（思想不受版权保护），但为**独立 clean-room 设计**——自有命名、自有结构，**不复用其 GPL-3.0 源码**。详见 §11。

`BridgeEnvelope` 用一个 `BubbleContent` tagged enum 承载四种交互态，UI 只认这套规范模型、不感知工具差异；新增工具只需新增 adapter（见 §4），渲染层零改动。

```swift
// VibePetCore/Bridge/BridgeEnvelope.swift
public struct BridgeEnvelope: Codable, Sendable {
    public let version: Int            // 协议版本，=1
    public let requestId: UUID         // 关联请求/响应
    public let source: SourceInfo      // 来源：工具 / 项目 / 会话
    public let content: BubbleContent  // 气泡渲染形态 + 是否需要回传
}

public struct SourceInfo: Codable, Sendable {
    public let tool: ToolKind          // .claudeCode / .codex
    public let projectName: String?    // cwd 的 basename，如 "VibePet"
    public let sessionShortId: String? // 会话短 id（前 6 位），多会话区分
    public let cwd: String?
}

public enum ToolKind: String, Codable, Sendable { case claudeCode, codex }

/// 气泡内容：每个 case = 一种渲染形态（见 §5.3）。
/// approval / question 需回传（hook 阻塞等待）；completion / status 为通知（非阻塞）。
public enum BubbleContent: Codable, Sendable {
    case approval(ApprovalContent)     // 允许 / 拒绝
    case question(QuestionContent)     // 结构化多选提问
    case completion(CompletionContent) // 任务完成（纯通知）
    case status(StatusContent)         // 轻量状态提醒

    public var needsResponse: Bool {
        switch self { case .approval, .question: true; case .completion, .status: false }
    }
}

// —— 审批 ——
public struct ApprovalContent: Codable, Sendable {
    public let title: String                   // 如 "Claude 想执行命令"
    public let risk: RiskLevel                 // 配色 + 默认焦点按钮
    public let preview: ActionPreview          // 紧凑动作摘要（不含完整 diff）
    public let allowLabel: String              // 默认 "允许一次"，可逐请求自定义
    public let denyLabel: String               // 默认 "拒绝"
    public let alwaysAllow: AlwaysAllowOption? // 非空 → 多显示「始终允许」按钮
    public let requiresTerminalApproval: Bool  // true → 仅能回终端处理（见 §5.3.4）
}

public struct AlwaysAllowOption: Codable, Sendable {
    public let label: String                   // 如 "始终允许 Bash"
    public let scopeHint: String               // 规则标识（如 toolName），由 adapter 落地
}

public enum RiskLevel: String, Codable, Sendable { case low, medium, high }

/// 紧凑动作预览：只放摘要，完整细节交给「跳回终端」。
/// （对齐 open-island 的克制做法：气泡不塞完整 diff，避免小气泡里塞不下。）
public enum ActionPreview: Codable, Sendable {
    case command(text: String)                              // 命令（等宽、截断显示）
    case fileChange(path: String, added: Int, removed: Int) // 文件变更（仅路径 + 增删行数）
    case fileRead(path: String)
    case network(target: String)
    case generic(summary: String)
}

// —— 结构化提问（对应 Claude Code 的 AskUserQuestion）——
public struct QuestionContent: Codable, Sendable {
    public let title: String
    public let questions: [QuestionItem]       // 通常 1 题，支持多题
}

public struct QuestionItem: Codable, Sendable {
    public let header: String                  // 短标签
    public let prompt: String                  // 题干
    public let options: [QuestionOption]
    public let multiSelect: Bool
}

public struct QuestionOption: Codable, Sendable {
    public let label: String
    public let detail: String?                 // 选项说明
    public let allowsFreeform: Bool            // true → 选中后填自由文本
}

// —— 完成通知（MVP 仅展示，不含回复；回复 Agent 留到 v1.1）——
public struct CompletionContent: Codable, Sendable {
    public let markdownSummary: String         // Markdown 渲染
    public let isError: Bool                   // 报错/中断 → 不同图标配色
}

// —— 轻量状态 ——
public struct StatusContent: Codable, Sendable {
    public let text: String                    // 单行提醒
}
```

### 3.3 回传响应

仅 `approval` / `question` 需要回传，沿**同一条阻塞中的 socket 连接**发回，`requestId` 配对。

```swift
// VibePetCore/Bridge/BridgeResponse.swift
public struct BridgeResponseEnvelope: Codable, Sendable {
    public let requestId: UUID
    public let response: BridgeResponse
}

public enum BridgeResponse: Codable, Sendable {
    case approval(ApprovalDecision)
    case question(QuestionAnswer)
    case `defer`                               // 通用兜底：超时 / App 未运行 → 工具回退原生流程
}

public enum ApprovalDecision: Codable, Sendable {
    case allowOnce
    case allowAlways(scopeHint: String)        // 对应 AlwaysAllowOption.scopeHint
    case deny(reason: String?)
}

public struct QuestionAnswer: Codable, Sendable {
    // header → 单值字符串：单选=label；多选=label 以 ", " 连接；
    // freeform("其他")=用户文本顶替 label（对齐 Claude Code CLI / Open Island，无独立 freeform/annotations 通道）
    public let answers: [String: String]
}
```

### 3.4 时序

**需回传类（`approval` / `question`，阻塞）：**
1. 工具触发 hook → `VibePetHooks` 从 stdin 读到工具原生事件 JSON。
2. CLI 经对应 `ToolAdapter` 归一化为 `BridgeEnvelope`（`content` 为 `.approval` 或 `.question`）。
3. CLI 连 socket 发送，**保持连接，等待** `BridgeResponseEnvelope`（用户响应倒计时默认 20s，可配，且必须小于对应工具 hook timeout）。
4. App `BridgeServer` 收到 → `PetController` 进入 `.decide` 态 → 弹对应气泡（允许/拒绝 或 多选题）。
5. 用户操作 → App 经同一连接回传 `BridgeResponseEnvelope`。
6. CLI 收到 → 经 `ToolAdapter` 转成该工具期望的 stdout JSON → `exit 0`。
7. 工具据此放行 / 取消 / 拿到已填答案继续。

**Fail-open（关键）：**
- App 未运行 / socket 连接失败 / socket 损坏：CLI 在 ≤ 2s 内输出 `defer`（Claude Code：无 JSON 的 `exit 0`；Codex：decline 决策），让工具回退**原生流程**，绝不卡住开发者。
- App 已连接但用户未响应：按配置的决策倒计时（默认 20s）等待；到点输出 `defer`。此时不要求 ≤ 2s，因为 20s 是用户可见的响应窗口。
- 所有工具侧 hook timeout 必须大于 VibePet 倒计时 + 1s 缓冲；若检测到配置不满足，安装器/设置页提示并拒绝写入该超时组合。

**通知类（`completion` / `status`，非阻塞）：**
- CLI 发送 envelope 后立即 `exit 0`；App 收到后弹无按钮气泡，数秒自动收起。

---

## 4. 工具适配层（ToolAdapter）

把每个工具的"事件格式 + 决策回写格式"差异封进各自 adapter，新增工具 = 新增一个 adapter。

```swift
// VibePetCore/Adapters/ToolAdapter.swift
public protocol ToolAdapter: Sendable {
    var tool: ToolKind { get }
    /// 解析工具从 stdin 传入的原生事件 → 归一化信封（nil 表示不关心此事件）
    func parseEvent(stdin: Data, env: [String: String]) throws -> BridgeEnvelope?
    /// 把用户回传转成该工具期望的 stdout 输出（区分 approval / question）
    func encodeResponse(_ response: BridgeResponse, for envelope: BridgeEnvelope) -> Data
}
```

### 4.1 ClaudeCodeAdapter
**解析（原生事件 → `BubbleContent`）**：

| Claude Code 事件 | 归一化为 | 说明 |
|---|---|---|
| `PreToolUse`（`tool_name` ≠ AskUserQuestion） | `.approval` | 从 `tool_input` 组装 `ActionPreview`：`Bash`→`.command`、`Edit/Write`→`.fileChange`、`Read`→`.fileRead`、`WebFetch`→`.network`；`alwaysAllow` 用 `tool_name` 填充。 |
| `PreToolUse`（`tool_name` = `AskUserQuestion`） | `.question` | 从 `tool_input.questions` 映射 `QuestionItem`/`QuestionOption`（header/options/multiSelect/freeform）。 |
| `Stop` | `.completion` | 优先从 payload 提取 summary / transcript 摘要；缺失时使用兜底文案，不假设事件一定携带 Markdown。 |
| `Notification` | `.status` | 单行提醒。 |

**回写（`BridgeResponse` → stdout JSON, `exit 0`）**：
- `approval.deny` → `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<原因>"}}`。`deny` 任何权限模式下都生效，可靠。
- `approval.allowOnce` → `permissionDecision:"allow"`。**注意**：特定版本存在 `allow` 不抑制原生弹窗的已知 bug，作尽力而为。
- `approval.allowAlways` → `allow` + 写入会话/持久权限规则（`scopeHint`=tool_name）。该能力必须先经 schema spike 验证；未验证通过时 adapter 不生成 `alwaysAllow`，UI 不显示"始终允许"。
- `question` → **关键机制**：返回 `permissionDecision:"allow"` 且带 `updatedInput`，把用户答案预填进 AskUserQuestion 的 `answers` 字段（按 question text 归集）→ 工具拿到已填输入，**不再弹原生提问**（纯 hook，无需注入按键）。该 schema 以当前 Claude Code 官方事件样例固化为 fixture；未验证通过时降级为 `.status` 提醒 + 回终端处理。
  > 📌 **M5-0 spike 结论（2026-06-20）：机制受支持，Claude Code ≥ 2.1.85。** 官方 changelog："PreToolUse hooks can now satisfy `AskUserQuestion` by returning `updatedInput` alongside `permissionDecision: "allow"`."。**答案格式**（据官方 Agent SDK user-input 文档 + 同源开源实现 Open Island 核实）：`answers` 按 question text 归集，单选=label、**多选="pass an array of labels or join them with `", "`"**（本实现用 `", "` 连接）、freeform "Other" 用**用户文本作为答案值**（*"custom text as the answer value"*，**无需 `annotations` 输出**）；CLI 对每题客户端追加 "Other"，本实现镜像为每题追加合成"其他"选项、回写时从 `updatedInput.questions` 剔除。注意 `updatedInput` 整体替换输入，须保留原 `questions`。已知版本 bug：[#15897](https://github.com/anthropics/claude-code/issues/15897)（多 hook 时 `updatedInput` 被忽略）、[#52822](https://github.com/anthropics/claude-code/issues/52822)（v2.1.119 回归仍弹原生）——靠 fail-open 倒计时兜底。详见 `Tests/Fixtures/claude/m5-question-spike-notes.md`。
- `defer` → 不输出 JSON，`exit 0`，回退原生流程。
- **注册位置**：`~/.claude/settings.json` 的 `hooks.PreToolUse` / `hooks.Stop` / `hooks.Notification`，command 指向稳定拷贝路径 `~/Library/Application Support/VibePet/bin/VibePetHooks`（见 §1.2，不引用 `.app` 包内路径）。

### 4.2 CodexAdapter
**解析**：

| Codex 事件 | 归一化为 | 说明 |
|---|---|---|
| `PermissionRequest` hook | `.approval` | shell 升权 / apply-patch 审批 → `.command` / `.fileChange`。 |
| `notify`（`agent-turn-complete`） | `.completion` | 任务完成提醒。 |
| 提问 / plan-mode 等需输入 | `.approval`（`requiresTerminalApproval=true`） | hook 暂不支持回填答案 → **降级**为"回终端处理"提示（见 §5.3.4）。 |

**回写**：`PermissionRequest` 支持 allow / deny / 不决定（decline）。多 hook 时 deny 优先；allow 放行；不决定则回退原生审批。
- `approval.allowOnce` / `allowAlways` → allow（`allowAlways` 的持久规则若 Codex 支持则写入，否则等同本次 allow）。
- `approval.deny` → deny。`question` 在 Codex 不直接作答 → `defer` + 引导回终端。
- 注意：`permissionDecision:"ask"`、`continue:false` 等字段当前"解析但未支持"，**MVP 只用 allow/deny/decline**。
- **注册位置**：Codex `config.toml` 的 hooks 段（`PermissionRequest`）与 `notify` 程序，均指向稳定拷贝路径 `~/Library/Application Support/VibePet/bin/VibePetHooks`（见 §1.2）。

> Codex 限制：`notify` 仅 `agent-turn-complete`，且 hook 不支持回填答案。故 Codex 的**审批与完成通知**可用，**结构化提问降级**为通知 + 跳回终端。Claude Code 则四态齐全。

**Codex hook trust / 并发约束（MVP 必须显式处理）**：
- Codex 非 managed command hook 可能需要用户在 `/hooks` 中 review/trust 后才会运行。VibePetSetup 只能完成"写入配置"，不能把"已写入"等同于"已生效"。
- 安装态分三类：`notInstalled`、`installedNeedsTrust`、`trustedActive`。无法自动读取 trust 状态时，设置页显示"已写入，需在 Codex /hooks 确认"，并把首次真实收到 Codex hook 事件作为 `trustedActive` 的运行时证据。
- Codex 会加载多个来源的匹配 hook，且同一事件的多个 command hook 可能并发启动。VibePet 不假设自己独占审批流；所有回写必须幂等，`requestId` 仅用于 VibePet 自身配对，不作为全局锁。

### 4.3 安装器与 manifest（VibePetSetup）

安装器对每个工具提供对称的三件套：`install` / `uninstall` / `status`（可由 CLI 子命令或 App 设置页按钮触发）。幂等与精确卸载靠一份 **manifest** 驱动，而非靠字符串猜测哪条配置是自己写的。

> **设计与版权说明**：manifest 驱动安装、install/uninstall/status 三件套、卸载保留用户条目、不覆盖用户自定义——这些是借鉴 open-vibe-island 的**做法/模式**（§11），为 clean-room 独立实现，不复用其 GPL-3.0 源码。

```
~/Library/Application Support/VibePet/install-manifest.json
```

```jsonc
{
  "version": 1,
  "hookBinaryVersion": "0.1.0",        // 当前 bin/VibePetHooks 版本，落后则重拷
  "tools": {
    "claudeCode": {
      "installed": true,
      "activationState": "trustedActive",
      "settingsPath": "~/.claude/settings.json",
      "writtenHooks": ["PreToolUse", "Stop", "Notification"],  // 仅记 VibePet 写入的
      "backupPath": "backups/settings.json.2026-06-17T...bak"
    },
    "codex": { "installed": false }
  }
}
```

- **install（幂等）**：检测工具配置存在性 → 写前展示将改动的文件/二进制/备份并经 App 确认（见 US-0/US-5）→ 备份原配置 → 拷贝/升级 `bin/VibePetHooks` → 把 hook 条目写入工具配置（command 指向稳定路径，§1.2）→ 写 manifest。已安装则跳过重复写入；二进制版本落后则仅重拷。Codex 写入后默认进入 `installedNeedsTrust`，直到用户完成 `/hooks` trust 或 VibePet 收到真实 Codex hook 事件后再标记为 `trustedActive`。
- **uninstall（精确）**：读 manifest，只移除其中 `writtenHooks` 记录的条目，**保留用户其它 hooks**；删 `bin/VibePetHooks` 与 manifest 对应项。
- **status**：读 manifest + 校验二进制版本 + 激活状态，返回每个工具 `未安装 / 已写入待信任 / 已启用 / 版本落后`，供 CLI 与设置页展示。
- **不覆盖用户自定义**：写入前若目标 hook 键已存在用户自己的非 VibePet 条目，则追加而不覆盖。
- **检测不到工具**：onboarding/设置页显示可读提示并允许跳过；hooks 非宠物陪伴的前置依赖。

---

## 5. 桌面宠物窗口与交互

### 5.1 浮动窗口
- `NSWindow` 无边框、透明背景（`isOpaque=false`、`backgroundColor=.clear`）、`level=.floating`、`collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary]`、`ignoresMouseEvents` 按区域动态控制。
- 内容用 SwiftUI 承载；窗口跟随宠物大小，仅宠物本体命中区域响应鼠标，透明处穿透。
- 宠物默认精灵框 120×120pt。

#### 5.1.1 定位与软吸附
- **坐标系**：所有定位基于 `NSScreen.main.visibleFrame`（已排除菜单栏与 Dock，故"贴底"= 站在 Dock 上方）。
- **默认落点**：首次启动置于主屏 `visibleFrame` 右缘内缩 24pt、贴底边。
- **自由拖动 + 软吸附（贴边 + 沿边滑动）**：拖动可达屏内任意处；`mouseUp` 时计算宠物外接框到四条边的距离，最近边距 < 40pt 则动画吸附到该边（内缩 8pt），**保留沿该边方向的坐标**（沿边滑动），靠近两条边时自然落到角。
- **主屏约束（MVP）**：宠物位置始终 clamp 进 `NSScreen.main.visibleFrame`；多屏放置 / 跨屏位置记忆排入后续版本。
- **持久化**：位置存 `config.json`（见 §6）；启动时若 `visibleFrame` 变化（分辨率 / 缩放调整）则 clamp 回可用区域。

### 5.2 宠物状态机（PetController）
```
        ┌──────────┐  启动/每日首次
   ┌───▶│  greet   │──────┐
   │    └──────────┘      ▼
   │                  ┌────────┐
   └──────────────────│  idle  │◀───────────────┐
                      └───┬────┘                 │
    completion/status 事件 │ approval/question 事件 │ 回传完成/气泡收起
                ┌─────────┴──────────┐           │
                ▼                    ▼            │
          ┌──────────┐         ┌──────────┐      │
          │  notify  │────────▶│  decide  │──────┘
          └──────────┘  (无按钮)└──────────┘ (审批/多选题)
```
- `idle`：呼吸/晃动待机动画。
- `greet`：打招呼动画 + 问候气泡。
- `notify`：提醒动画 + 文案气泡（承载 `completion` / `status`），自动收起。
- `decide`：高亮提醒 + 可交互气泡（承载 `approval` / `question`），回传后回 `idle`。

### 5.3 气泡（SpeechBubble）

气泡是宠物与用户沟通的唯一界面，内容完全由 `BubbleContent`（见 §3.2）驱动，一个 `case` 对应一种渲染模式。设计原则对齐 open-island 的**克制**：气泡里只放摘要，重细节（完整 diff、长输出）交给"跳回终端"。

| 渲染模式 | `BubbleContent` | 有按钮 | 自动收起 | 是否回传 |
|---|---|---|---|---|
| 问候 | （本地，非事件） | 否 | 是（3–4s） | 否 |
| 状态 | `.status` | 否 | 是（6–8s，悬停暂停） | 否 |
| 完成 | `.completion` | 否（可展开 Markdown） | 是（8–10s，悬停暂停） | 否 |
| 审批 | `.approval` | 是（拒绝/允许一次/始终允许） | 否（倒计时到点 fail-open） | 是 |
| 提问 | `.question` | 是（选项按钮 + 提交） | 否（倒计时到点 fail-open） | 是 |

**通用规则**
- SwiftUI 视图，带指向宠物的小尾巴。**象限感知锚定**：按宠物中心落在 `visibleFrame` 的象限决定开向——下半屏→向上、上半屏→向下；右半屏→向左展开、左半屏→向右展开（如右下角→往左上）。
- **尾巴跟踪**：小尾巴始终指向宠物中心，且其在气泡边上的落点**独立跟踪宠物**，故气泡被边界挤动后仍精确指向宠物。
- **边界避让**：锚定后将气泡整体 clamp 进 `visibleFrame`（距边 12pt）；上方实在放不下（宠物贴顶）才翻到下方；左右都不足则内部滚动而非撑宽（见下"宽度"规则）。
- **拖动期间**：拖动宠物时气泡先收起，`mouseUp` 后按新象限重新锚定弹回。
- 五种渲染态（问候 / 状态 / 完成 / 审批 / 提问）共用上述锚定与避让逻辑。
- 跟随系统明暗主题；宽度自适应，最小 240pt、最大 380pt；超长内容内部滚动而非无限撑高。
- 遵守"减弱动态效果"（Reduce Motion）：关闭弹跳，改用淡入淡出。
- 文字元素提供 VoiceOver 标签；按钮最小点击区 28×28pt。
- 头部统一显示来源：`工具图标 · 项目名(source.projectName) · 会话短id(source.sessionShortId)`，多会话一眼区分谁在请求。

#### 5.3.1 问候气泡（greeting）
- 内容：随时段变化的问候 + 宠物名，1 行，可带表情。示例：早 `早上好呀，今天也一起加油 🐾`；晚 `这么晚还在写代码，注意休息哦`；启动 `我回来啦！有需要决策的我会叫你～`。
- 行为：打招呼动画，3–4s 后淡出；点击宠物可手动唤出。

#### 5.3.2 状态 / 完成气泡（status / completion）
- **状态 `.status`**：单行图标 + `text`，6–8s 自动收起。示例 `💬 Claude 在等待你的输入`。
- **完成 `.completion`**：图标 + `markdownSummary`（Markdown 渲染，最多约 6 行后内部滚动）；`isError=true` 用警示图标/红色。示例 `✅ 这轮跑完了：新增 3 个测试，全部通过`。
- 行为：8–10s 自动收起，悬停暂停；可点击展开完整 Markdown。**MVP 不含"回复 Agent"**（留到 v1.1）。
- 通知不打断进行中的审批/提问气泡（优先级见 §5.3.5）。

#### 5.3.3 审批气泡（approval card）
布局三段——**头部（来源+风险）/ 主体（紧凑动作摘要）/ 底部（倒计时+按钮）**：

```
        ╭───────────────────────────────────────╮
        │  🅒 Claude Code · VibePet · a1b2c3   ⚠️高 │  ← 头部
        ├───────────────────────────────────────┤
        │  Claude 想执行命令                       │  ← ApprovalContent.title
        │  ┌─────────────────────────────────┐   │
        │  │ rm -rf build/                   │📋 │  ← preview（紧凑，不放完整 diff）
        │  └─────────────────────────────────┘   │
        ├───────────────────────────────────────┤
        │  ⏳18s   [拒绝 esc] [允许一次 ⌘↩] [始终允许]│  ← 底部：倒计时 + 按钮（文案可定制）
        ╰───────────────────────────────────────╯
```

**主体——按 `ActionPreview` 渲染（紧凑）**：

| case | 渲染 |
|---|---|
| `.command(text)` | 等宽显示命令（超 3 行截断 + "在终端查看"）；命中危险模式（`rm -rf`、`sudo`、`curl … \| sh`、`git push --force`）标红。 |
| `.fileChange(path, +N, −M)` | 文件名（完整路径悬停）+ `+N/−M` 行数徽标。**不内嵌 diff**，完整 diff 跳回终端看。 |
| `.fileRead(path)` | 单行路径（通常 `.low`）。 |
| `.network(target)` | 目标域名/URL + 外链图标，标注"将访问网络"。 |
| `.generic(summary)` | 纯文本兜底。 |

**风险分级（`risk`）→ 视觉与默认焦点**：
- `.low`：中性配色，默认焦点"允许一次"。
- `.medium`：黄色头部条，无默认焦点（防手滑）。
- `.high`：红色头部条，**默认焦点"拒绝"**，"允许"需明确点击（不响应单独回车），降低误放行。
- 风险由 `ToolAdapter` 按工具名 + 命令模式启发式判定（规则可配置、可单测）。

**底部——倒计时 + 按钮**（按钮文案来自 `allowLabel`/`denyLabel`，可逐请求定制）：
- 倒计时默认 20s（可配），到点 CLI fail-open 返回 `defer`，气泡更新为"⏰ 已超时，已交回原生审批"并 2s 后淡出。
- **拒绝**（`esc`）→ `deny`，可选展开"原因"输入框作 `permissionDecisionReason` 回传。
- **允许一次**（`⌘↩`）→ `allowOnce`。
- **始终允许**（仅当 `alwaysAllow != nil` 且 schema spike 已验证）→ `allowAlways(scopeHint)`；未验证通过时不显示该按钮。
- `requiresTerminalApproval=true` 时（如 Codex 的部分场景）：不显示允许/拒绝，改为单个**"回终端处理"**按钮 + 提示文案（MVP 仅聚焦/复制提示，真正跳转留 v1.1）。

#### 5.3.4 提问气泡（question card）
对应 Claude Code 的 `AskUserQuestion`。逐题渲染 `QuestionItem`：

```
        ╭───────────────────────────────────────╮
        │  🅒 Claude Code · VibePet · a1b2c3       │
        ├───────────────────────────────────────┤
        │  选择数据库方案                          │  ← QuestionContent.title
        │  [DB] 用哪个数据库？                      │  ← QuestionItem.header / prompt
        │   ◉ SQLite   轻量、零依赖（推荐）          │  ← QuestionOption(label / detail)
        │   ○ Postgres 需要独立服务                 │
        │   ○ 其它…（自由填写）                     │  ← allowsFreeform → 选中后出现文本框
        │            ⏳18s        [ 提交 ⌘↩ ]        │
        ╰───────────────────────────────────────╯
```

- 单选用单选圈、`multiSelect=true` 用复选框；选项展示 `label` + 次行灰字 `detail`。
- `allowsFreeform=true` 的选项选中后展开文本框。
- 提交（`⌘↩`）→ 回传 `QuestionAnswer`（`answers` 按 `header` 归集为单值字符串，freeform 文本内联进值）；schema spike 通过时 adapter 经 `updatedInput` 预填回 AskUserQuestion（见 §4.1），未通过时降级为提醒 + 回终端处理。
- 倒计时到点同样 fail-open `defer`（回退工具原生提问）。
- **Codex 无此卡**：其提问降级为审批卡的 `requiresTerminalApproval` 形态（见 §4.2）。

#### 5.3.5 队列与并发
- 多个需回传气泡（多终端/多会话）：以 `requestId` 各自独立，采用**卡牌堆叠 + 露头**几何——同一锚点处叠放，顶层卡完整可操作，身后最多 2 张各露出一条细边（向屏幕内侧上方错开 6pt），细边显示来源标签 `工具·会话短id · 动作摘要`；顶部显示 `还有 N 个待处理`。
- **顺序**：FIFO，最早到达（最接近超时）者在顶层，避免请求未被看到即超时。
- **各自倒计时**：露头卡超时则静默 fail-open（返回 `defer`）并从栈中移除、计数减一；顶层处理完滑出，下一张升为顶层。
- 优先级：审批/提问（`decide`）> 完成/状态（`notify`）> 问候（`greet`）。`decide` 在场时通知不弹气泡，仅在宠物头顶累计小红点，清空后再汇总补发。

#### 5.3.6 可定制与扩展性
- **加新工具**：只实现新 `ToolAdapter`（解析 → `BubbleContent`，回传 → stdout），渲染层零改动。
- **按请求定制**：`allowLabel`/`denyLabel`/`alwaysAllow.label`/`title` 均可逐请求自定义文案。
- **加新交互态**：给 `BubbleContent` 增一个 `case` + 一个气泡子视图即可；现有态不受影响。
- **主题/皮肤**：气泡样式集中在一处 `BubbleTheme`（配色/圆角/字体），便于后续随宠物皮肤切换；内容与样式分离。

### 5.4 菜单栏 & 设置
- `NSStatusItem`：显示/隐藏宠物、切换宠物、导入新照片、打开设置、退出。
- 设置页：选择启用的工具（Claude Code / Codex）、一键安装/卸载 hooks（调用 `VibePetSetup`，据 manifest 显示各工具安装态/版本，见 §4.3）、决策超时时长、开机自启、生成器选择（MVP 仅本地）。
- 首启 onboarding（US-0）：欢迎 → 生成宠物（§5.5）→ 安装 hooks（§4.3，只列检测到的工具，可跳过）→ 完成；仅首次出现。

### 5.5 导入 → 生成面板（PetImportPanel）
单一紧凑面板承载"照片 → 宠物"全流程，内容随状态原地变形（无多步向导翻页）；首次启动与"换宠物 / 导入新照片"复用同一面板。

```
        ┌────────┐ 导入图片(拖拽/选图)  ┌──────────┐ 抠图完成   ┌──────────┐ 确认  ┌────────┐
   ─────▶│  idle  │────────────────────▶│ generating│──────────▶│  result  │──────▶│ placed │
        └────────┘  (自动开始抠图)      └────┬─────┘            └────┬─────┘       └────────┘
             ▲                               │ noSubject/失败          │ "换一张"
             │                               ▼                        │
             │                          ┌─────────┐                   │
             └──────────────────────────│  error  │◀──────────────────┘
                     "换一张"/"重试"      └─────────┘
```

- **idle**：拖拽区 + "选择文件"；接受 JPG/PNG/HEIC。拖入或选定即转 `generating`（**导入即自动抠图**，无独立"生成"按钮）。
- **generating**：原图淡显 + 进度（`PetGenerator.generate` 的 `progress` 回调驱动）；调用 §2.3 的 `GenerationService`。
- **result**：棋盘格背景预览透明精灵 + 命名输入框（预填占位名，可留空跳过）+ 「换一张」「放上桌面」。
- **placed**：写入 `PetAssetStore` 与 `config.activePetID`，面板关闭，宠物落到桌面默认右下角（见 §5.1.1）并进入 `idle` 待机。
- **error**：`GenError`（如 `.noSubject`）→ 面板内可读提示 + 「换一张」「重试」，不产生半成品资源（见 §7）。
- 与窗口/气泡解耦：面板是独立的导入 UI，**不复用** `SpeechBubble`；生成逻辑全部走 `VibePetCore` 的生成管线，面板仅驱动状态与展示。

---

## 6. 持久化与配置

目录：`~/Library/Application Support/VibePet/`
```
VibePet/
├── bin/                 # 稳定路径的 hook 二进制拷贝（见 §1.2）
│   └── VibePetHooks     # 工具配置指向此处，与 .app 位置解耦
├── pets/                # 各宠物素材（PNG/HEIC + meta.json）
│   └── <uuid>/sprite.png, meta.json
├── config.json          # 活动宠物、启用工具、超时、生成器ID、宠物位置(主屏 visibleFrame 内)等
├── install-manifest.json # 记录已为哪些工具写入哪些 hook 条目 + 二进制版本(见 §4.3)
├── bridge.sock          # 运行时套接字
└── backups/             # 写入工具配置前的备份
```
- `config.json` 由 `VibePetCore/Persistence/ConfigStore` 读写（`Codable`）。
- 宠物素材由 `PetAssetStore` 管理；切换宠物即切 `activePetID`。

---

## 7. 错误处理与可靠性

| 场景 | 处理 |
|---|---|
| 抠图无主体/失败 | 抛 `GenError`，UI 提示换图/重试，不产生半成品资源。 |
| App 未运行时触发 hook | CLI 连接失败 → 立即 `defer` fail-open，工具走原生流程。 |
| 回传超时（审批/提问） | App 已连接但用户未响应时，按决策倒计时（默认 20s）到点 → `defer` fail-open。 |
| socket 损坏/残留 | App 启动时清理并重建 socket；CLI 连接失败即 fail-open。 |
| 工具配置被用户手改 | 安装幂等校验；卸载按标记精确移除；写入前备份。 |
| `allow` 抑制 bug（Claude Code 特定版本） | 优先保障 `deny`；`allowOnce` 尽力而为，必要时退化为再次原生确认（不影响安全）。 |
| `allowAlways` / `updatedInput` schema 未验证或版本不兼容 | 隐藏"始终允许"；提问卡降级为提醒 + 回终端处理，不阻塞审批主链路。 |
| 完成事件无摘要字段 | completion 气泡显示兜底文案，不因缺少 Markdown 摘要丢弃事件。 |
| Codex hook 已写入但未 trust | 设置页显示"待信任"，引导 `/hooks`；验收不把写入配置等同于生效。 |
| 并发多个需回传气泡 | 以 `requestId` 关联；堆叠展示，仅最上层可操作（见 §5.3.5）。 |
| Codex 提问无法回填 | 降级为 `requiresTerminalApproval` 审批卡 + 引导回终端。 |

**总原则：VibePet 任何异常都不得阻塞用户的 AI 工具（fail-open 永远兜底）。**

---

## 8. 测试策略

### 8.1 单元测试（`VibePetCore`，无 UI 依赖）
- `BridgeEnvelope`/`BubbleContent`/`BridgeResponseEnvelope` 编解码往返（含四种 `content` case）。
- `ClaudeCodeAdapter`：给定样例 `PreToolUse`（Bash/Edit/Read/WebFetch/AskUserQuestion）、`Stop`、`Notification` 事件 JSON，断言归一化为正确 `BubbleContent`；给定 `BridgeResponse`，断言 stdout 字节与 exit 语义（含 `question` 的 `updatedInput` 预填）。
- `CodexAdapter`：`PermissionRequest`/`notify` 解析；提问降级为 `requiresTerminalApproval`。
- 风险分级启发式：危险命令模式 → `.high`。
- `ConfigStore` / `PetAssetStore` 读写与幂等；安装器对样例 `settings.json` / `config.toml` / `hooks.json` 注入与精确移除（幂等、备份、Codex `installedNeedsTrust` 状态）。
- Claude Code 能力 spike fixtures：`allowAlways`、`AskUserQuestion updatedInput`、`Stop` payload 摘要字段分别用当前版本样例固化；不通过时断言对应降级分支。

### 8.2 生成质量基准（离线）
- 20 张固定测试照片集，按 `clearSubject` / `edgeHard` / `lowContrast` / `multiSubject` 标签统计；跑 `LocalCutoutGenerator`，记录耗时与人工边缘打分；分别校验清晰主体子集 ≥ 90% 与全量 ≥ 80%，并输出每个标签组的通过率。

### 8.3 端到端（脚本化）
- 模拟 Claude Code `PreToolUse`（Bash）：喂 `VibePetHooks` stdin，App 运行态下断言审批气泡出现 ≤ 500ms、点"拒绝" → stdout 为 `deny` JSON、点"允许一次" → `allow` JSON。
- 模拟 Claude Code `AskUserQuestion`：断言提问气泡渲染选项；提交 → stdout 为 `allow` + `updatedInput` 含预填 `answers`。
- 模拟 Codex `PermissionRequest` 审批回路；提问场景断言降级提示；Codex 安装态覆盖"已写入待信任"与"收到真实事件后标记启用"。
- Fail-open：App 关闭态/连接失败态喂事件，断言 CLI ≤ 2s 内 `defer` 退出；App 已连接但用户未响应时，断言默认 20s 倒计时后 `defer`。

### 8.4 手动验收（Demo 脚本）
导入一张宠物照 → 见到精灵出现并呼吸 → 在真实 Claude Code 会话里触发一次需审批操作 → 宠物气泡弹出 → 点"拒绝" → 确认 Claude Code 取消该操作。即 PRD 的端到端成功标准。

---

## 9. MVP 里程碑（Milestones）

本节把 MVP（v0.1）拆为 **7 个可验收的里程碑**。里程碑按依赖关系串行推进，每个都给出**目标 / 范围（含本方案章节锚点）/ 交付物 / 退出标准（绑定 PRD 用户故事与 KPI）/ 依赖**。M0–M2 是地基（无桥接也能独立演示），M3–M5 逐步打通决策闭环，M6 完成两工具集成与发布打磨。

> 每个里程碑的中粒度 task 拆解（含验收标准 / 依赖 / 涉及文件）见配套文档：[《VibePet MVP 任务拆解》](./VibePet-MVP-任务拆解.md)。

> 退出标准里引用的 US-x 见 [PRD §2.2](./VibePet-PRD.md)，KPI 见 [PRD §1 成功标准](./VibePet-PRD.md)。

### 依赖关系总览

```
M0 脚手架 + Bridge 模型
   ├──▶ M1 生成管线（照片→精灵）────┐
   └──▶ M3 通知链路（非阻塞气泡）    │
                  │                  ▼
                  └──▶ M2 宠物窗（窗口/动画/菜单栏）
                              │            │
                              ▼            ▼
                        M4 审批闭环   （M1 提供宠物素材）
                        (Claude Code)
                              │
                              ▼
                        M5 提问闭环
                        (AskUserQuestion)
                              │
                              ▼
                        M6 Codex 适配 + 安装器 + 发布打磨
```

---

### M0 · 脚手架与 Bridge 数据模型

- **目标**：可编译、可单测的工程骨架与全部归一化数据模型就位，为后续所有里程碑提供地基。
- **范围**：Swift Package + 四 target 骨架（§1.1）；`VibePetCore` 实现 `BridgeEnvelope` / `BubbleContent`（四 case）/ `BridgeResponse`（§3.2、§3.3）；`ToolAdapter` 协议（§4）；Unix domain socket 基础设施（`BridgeServer` / `BridgeClient`，§3.1）；`ConfigStore` 骨架（§6）。
- **交付物**：四 target 可 `swift build`；编解码与 socket 收发的单元测试（§8.1 第 1、5 条的模型部分）。
- **退出标准**：
  - 四种 `content` case 编解码往返测试全绿（§8.1）。
  - `BridgeClient` 与 `BridgeServer` 在本地能完成一次 newline-delimited JSON 往返。
- **依赖**：无（起点）。

### M1 · 本地生成管线（照片 → 精灵）

- **目标**：脱离 UI，离线把一张照片抠成带透明通道的精灵 PNG。
- **范围**：`PetGenerator` 协议 + `LocalCutoutGenerator`（Vision `VNGenerateForegroundInstanceMaskRequest`，取最大主体，§2.1）；`PetAsset` / `PetAssetStore`（§2、§6）；`GenerationService` 选择器（§2.3）；`GenError` 语义（§7）。
- **交付物**：CLI/测试入口跑通"图片 → `sprite.png` + `meta.json`"；离线生成质量基准脚本（§8.2，20 张测试集）。
- **退出标准**（对应 **US-1**、抠图 KPI）：
  - 抠图 P50 ≤ 3s、P95 ≤ 8s（Apple Silicon）。
  - 20 张固定测试集：清晰主体子集边缘可用率 ≥ 90%，全量边缘可用率 ≥ 80%。
  - 无主体 → 抛 `GenError.noSubject`，不产生半成品资源。
- **依赖**：M0。

### M2 · 桌面宠物窗

- **目标**：宠物能"活"在桌面——透明浮动、待机/打招呼动画、拖动吸附、菜单栏控制。
- **范围**：透明无边框 `NSWindow`（§5.1）+ SwiftUI 宠物；待机呼吸/晃动 + 打招呼动画（§2.1 末、§5.2）；拖动 + 软吸附 + 主屏 clamp + 位置持久化（§5.1.1）；`NSStatusItem` 菜单栏（§5.4）；导入→生成面板 `PetImportPanel`（§5.5，复用 M1 管线）；首启 onboarding 骨架（US-0 ①②）。
- **交付物**：可运行的 App——导入照片 → 宠物落桌面 → 呼吸 → 可拖动吸附 → 菜单栏隐藏/显示/切换/退出。
- **退出标准**（对应 **US-1 / US-2 / US-0 的 ①②**）：
  - 透明区域鼠标穿透，仅宠物本体响应；启动出现在主屏右下角并 clamp 在 `visibleFrame` 内。
  - 拖动松手近边自动吸附、沿边滑动、记住位置。
  - 启动/每日首次播放打招呼气泡（本地，非事件驱动）。
- **依赖**：M0、M1。

### M3 · Bridge 通知链路（非阻塞气泡）

- **目标**：打通 hook CLI ↔ App 的端到端通道，先跑通**不需回传**的通知态。
- **范围**：`VibePetHooks` CLI 骨架（读 stdin → adapter → 连 socket → 发送，§1.1、§3.4）；App 侧 `BridgeServer` 路由 → `PetController` 状态机 `idle/greet/notify`（§5.2）；`SpeechBubble` 渲染 `.status` / `.completion`（§5.3.1–5.3.2）；`ClaudeCodeAdapter` 的 `Stop` / `Notification` 解析（§4.1）。
- **交付物**：喂 `VibePetHooks` 一条 `Stop`/`Notification` 事件 → 宠物头顶弹出无按钮气泡并自动收起。
- **退出标准**（对应 **US-4**）：
  - `completion` / `status` 气泡正确渲染、悬停暂停、数秒自动收起。
  - App 未运行时 CLI 立即 `defer` 退出（fail-open 雏形）。
- **依赖**：M0、M2。

### M4 · 审批闭环（Claude Code `PreToolUse`）

- **目标**：完成 MVP 的核心价值——决策类操作在气泡里一键允许/拒绝并真实回传。
- **范围**：`PreToolUse` 阻塞回路（CLI 保连接等回传，超时 fail-open，§3.4）；`PetController.decide` 态（§5.2）；审批气泡（拒绝/允许一次/始终允许 + 倒计时，§5.3.3）；`ActionPreview` 紧凑渲染 + 风险分级启发式（§5.3.3、§4.1）；`ClaudeCodeAdapter` 的 `PreToolUse → .approval` 解析与 `deny/allow/allowAlways` 回写（§4.1）；队列与并发堆叠（§5.3.5）；象限锚定/边界避让（§5.3 通用规则）。
- **交付物**：真实 Claude Code 会话触发需审批操作 → 气泡弹出 → 点"拒绝"工具取消 / 点"允许一次"工具放行。
- **退出标准**（对应 **US-3**、端到端闭环与延迟 KPI、Fail-open KPI）：
  - 端到端 Demo 成功：照片→精灵→桌面→`PreToolUse`→气泡→点"拒绝"→工具调用被真实取消（§8.4）。
  - 工具触发到气泡出现 ≤ 500ms。
  - App 未运行/连接失败 → CLI ≤ 2s `defer` fail-open；用户未响应 → 默认 20s 倒计时后 `defer`，成功率 100%（§8.3）。
  - `deny` 路径可靠；`allow` 尽力而为并按 §7 处理已知 bug。
- **依赖**：M3（M4-7 队列堆叠与 M4-8 Demo 并行推进，不阻塞 Demo 验收）。

### M5 · 提问闭环（`AskUserQuestion`）

- **目标**：结构化多选题在气泡内作答，经 `updatedInput` 预填回工具。
- **范围**：先完成 `AskUserQuestion updatedInput` schema spike；通过后 `ClaudeCodeAdapter` 拦截 `PreToolUse(tool=AskUserQuestion) → .question`（§4.1）；提问气泡渲染单选/多选/自由文本（§5.3.4）；`QuestionAnswer` 回传 + `updatedInput` 预填回写（§3.3、§4.1）。若 spike 未通过，MVP 降级为提醒 + 回终端处理。
- **交付物**：schema spike 通过时，触发 `AskUserQuestion` → 气泡渲染选项 → 提交 → stdout 为 `allow` + 含预填 `answers` 的 `updatedInput`，工具不再弹原生提问；schema spike 未通过时，交付降级提醒 + 回终端处理。
- **退出标准**（对应 **US-3b**）：
  - schema spike 通过时：提问气泡提交后答案正确预填，原生提问被抑制（§8.3）。
  - schema spike 未通过时：降级气泡正确提示回终端处理，不阻塞原生提问。
  - 未作答超时 → fail-open 回退原生提问。
- **依赖**：M4。

### M6 · Codex 适配 + 安装器 + 发布打磨

- **目标**：补齐第二工具、一键安装/卸载、设置页与发布所需打磨，达到可分发的 MVP。
- **范围**：
  - **Codex 适配**：`CodexAdapter` 的 `PermissionRequest` 审批回路 + `notify(agent-turn-complete)` 完成通知 + 提问降级为 `requiresTerminalApproval`（§4.2、§5.3.3 末）。
  - **安装器**：`VibePetSetup` 拷贝二进制到稳定路径（§1.2）+ manifest 驱动幂等写入/精确卸载/status（§4.3）+ 写前确认与备份（US-5）+ App 设置页按钮（§5.4）。
  - **发布打磨**：设置页（启用工具、超时、开机自启、生成器选择，§5.4）、`BubbleTheme`、错误提示统一（§7）、签名与公证、基准测试达标。
- **交付物**：两工具均可一键安装/卸载并显示安装态；Codex 审批回路与提问降级可用；签名公证后的可分发包。
- **退出标准**（对应 **US-5 / US-3（Codex）/ US-4（Codex）/ US-0 的 ③**）：
  - 安装幂等、卸载精确（保留用户其它 hooks）、写前备份与确认（§8.1 安装器测试、US-5）。
  - Codex 安装态能区分"已写入待信任"与"已启用"，并覆盖 `/hooks` trust 引导或真实事件激活证据。
  - Codex `PermissionRequest` 审批回路通过；提问降级提示正确（§8.3）。
  - onboarding 第 ③ 步只列检测到的工具、可跳过（US-0）。
  - §8 全部测试通过；§1 全部 KPI 达标。
- **依赖**：M5（同时复用 M0 的 `ToolAdapter` 抽象与 §3 协议）。

### 里程碑 ↔ 用户故事 / KPI 映射

| 里程碑 | 主要用户故事 | 关联 KPI |
|---|---|---|
| M0 | —（地基） | — |
| M1 | US-1 | 抠图耗时 P50/P95、抠图可用率 |
| M2 | US-1、US-2、US-0①② | — |
| M3 | US-4 | Fail-open（雏形） |
| M4 | US-3 | 端到端闭环、决策回路延迟 ≤500ms、Fail-open 100% |
| M5 | US-3b | —（复用决策回路延迟） |
| M6 | US-5、US-3/US-4（Codex）、US-0③ | 全部 KPI 验收 |

---

## 10. 参考项目使用指南

### 10.1 open-vibe-island（架构参考，GPL-3.0）

**项目地址**：https://github.com/Octane0411/open-vibe-island

**项目做了什么**：open-vibe-island 是 macOS 上类似 VibePet 的开发者桌面助手。其核心与 VibePet 高度重合：一个被 AI 工具 hook 调用的轻量 CLI 二进制，通过 Unix domain socket 把工具事件转发给宿主 App（SwiftUI），对决策类事件阻塞等待气泡回传；宿主 App 侧有 socket 服务器 + 数据驱动的气泡 UI；安装器负责把 CLI 二进制拷贝到稳定路径并幂等写入工具配置。这条技术路线的可行性与低延迟已在该项目中得到验证。

**哪些思路可以参考**（思想/架构模式不受版权保护）：

| 模块 / 思路 | 参考价值 | VibePet 对应 |
|---|---|---|
| hook CLI → Unix socket → App 通信架构 | 验证此路线在 macOS 上可行且延迟满足 ≤500ms | §1、§3 |
| 安装时把 hook 二进制拷到 `Application Support/bin/` | 解决 hook 路径随 .app 移动/重命名失效的问题 | §1.2 |
| manifest 文件驱动安装 / 卸载状态追踪 | 比字符串猜测更可靠的幂等安装与精确卸载 | §4.3 |
| 气泡内只放摘要，不内嵌完整 diff（克制原则） | 小气泡塞 diff 体验差；重细节交给"跳回终端" | §5.3 |
| 规范事件 + 数据驱动渲染（adapter 模式） | 新增工具只需新增 adapter，渲染层零改动 | §3.2、§4 |
| install / uninstall / status 三件套对称设计 | 安装行为可预期、可逆、可查 | §4.3 |

**何时优先查阅 open-vibe-island**（先查、再凭官方 API 独立实现）：
- 遇到 **Unix socket 在 macOS 上如何稳定收发 newline-delimited JSON** 的实现疑问。
- 遇到 **hook CLI 在 App 未运行时如何快速 fail-open**（连接超时策略）的实现疑问。
- 遇到 **安装器如何幂等写入 `settings.json` / `config.toml`、如何精确卸载**（只删自己写的条目）的实现疑问。
- 遇到 **气泡 UI 如何跟随窗口边缘锚定、尾巴指向宠物**的布局实现疑问。
- 总之：**架构可行性印证**类疑问 → 查 open-vibe-island 验证方向；然后凭官方文档与自有 fixture 独立编写，不照抄代码。
- 我们的项目简单来说就是在重写 open-vibe-island 的基础上增加一个宠物，所有有关 vibe-island 的内容都可以参考

**不应做的事（版权边界，详见 §11）**：
- 不以"open-island 这么写的"作为实现证据；每个涉及 hook/adapter/安装器的 PR 必须附官方文档链接或自有 fixture。
- 高风险模块（adapter、安装器、socket 协议）优先由未深入阅读过其源码的人复核 diff。

### 10.2 官方 API 参考（实现直接依据）

> 这些是每个实现 task 的**第一手依据**，优先级高于 open-vibe-island。

| 能力 | 文档 |
|---|---|
| Apple Vision 主体抠图（`VNGenerateForegroundInstanceMaskRequest`，macOS 14+） | Xcode 内置文档 / WWDC 2023 "Lift subjects from images in your app" |
| Claude Code Hooks（`PreToolUse` 的 `permissionDecision`、`updatedInput`） | https://code.claude.com/docs/en/hooks-guide |
| Codex Hooks（`PermissionRequest` 生命周期 hook、`notify` 程序） | https://developers.openai.com/codex/hooks |
| macOS 浮动透明窗口、NSStatusItem | Apple Developer Documentation |

### 10.3 未来生成器参考（v1.1 / v2.0，MVP 不实现）
- **TripoSR**（MIT）：单图快速 3D 生成，v2.0 备选。
- **Hunyuan3D**：高保真 3D，部分权重为**非商用**，接入前须单独核查许可证。
- **云端 img2img**（v1.1）：接口在 `CloudStylizeGenerator` 占位，需用户显式开启并自带 API key。

---

## 11. 开源证书与 clean-room 边界

open-vibe-island 采用 **GPL-3.0**（传染性 copyleft）：直接复制或衍生其源码，会要求 VibePet 整体以 GPL-3.0 开源。为保留许可证灵活性，遵守以下边界：

- **可以借鉴的是「思想/模式」**（不受版权保护）：规范事件 + 数据驱动渲染、hook CLI + Unix socket 桥接、安装时拷贝二进制到稳定路径、审批/提问/完成的交互形态等架构思路。
- **不复用其源码**：所有模型（`BridgeEnvelope`/`BubbleContent`/`ApprovalContent`/…）均为独立设计与命名，不照抄其 `AgentEvent`/`PermissionRequest`/视图代码，不做近似改写（clean-room）。
- **直接依据的是工具方公开 API**：`PreToolUse` 的 `permissionDecision`/`updatedInput`、`AskUserQuestion` 的 `answers`/`annotations` schema、Codex `PermissionRequest`/`notify` —— 这些来自 Claude Code / Codex 官方文档与工具 schema，使用它们不构成对 open-island 的衍生。
- **实现期纪律**：阅读 open-island 仅用于「理解机制/印证可行性」，落码时凭官方文档与自有设计独立编写；不在仓库中保留其源码片段。每个涉及 hook/schema/安装器的实现 PR 必须附上所依据的官方文档链接或本机事件 fixture，不能以 open-island 代码作为实现证据。
- **隔离建议**：若实现者已经深入阅读过 open-island 具体源码，涉及同一模块落码前先写一份自有接口设计/测试 fixture，再按测试实现；高风险模块（adapter、安装器、socket 协议）优先由未读源码的人复核 diff，确认不存在近似改写。
- 引入任何第三方依赖（生成模型权重、库）时单独核对其许可证（如 TripoSR MIT、部分 Hunyuan3D 权重为非商用）。
