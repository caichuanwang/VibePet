## Context

VibePet 是一个 macOS 14+ 桌面宠物应用（Swift 6.x / SwiftUI + AppKit，纯原生），通过 hook 进程拦截 AI 编码工具（Claude Code / Codex）的事件，在桌面宠物气泡里完成审批/提问/通知。技术方案选定**方案 A**：单一 Swift Package + 四 target，hook 进程与宿主 App 经 Unix domain socket 通信。

当前仓库只有文档，无代码。M0 要立起地基：工程骨架 + 全部归一化数据模型 + socket 基础设施 + 配置存储，使后续里程碑（M1 生成、M2 宠物窗、M3 通知链路）都能基于稳定契约并行推进。

参考资料：技术方案 §1（架构）、§3（Bridge 协议）、§4（ToolAdapter）、§6（持久化）、§8.1（单测）；版权边界见 §11（clean-room，不复用 open-vibe-island 的 GPL-3.0 源码，仅借鉴思路）。

## Goals / Non-Goals

**Goals:**

- 单一 Swift Package，四 target（`VibePetCore` library + `VibePetApp`/`VibePetHooks`/`VibePetSetup` executable），`swift build && swift test` 全绿，`VibePetApp` 能空跑最小窗口。
- `VibePetCore` 落地全部归一化模型：`BridgeEnvelope` / `BubbleContent`（四 case）/ `BridgeResponseEnvelope`，编解码往返单测全绿。
- `ToolAdapter` 协议就位，可被 mock 实现编译。
- Unix domain socket 基础设施（`BridgeServer`/`BridgeClient`/`SocketPath`）完成一次 newline-delimited JSON 本地往返，权限 0700/0600，启动清理残留 socket。
- `ConfigStore` 骨架读写 `config.json`，缺文件返回默认配置。

**Non-Goals:**

- 不实现任何具体工具 adapter 的解析/回写逻辑（`ClaudeCodeAdapter`/`CodexAdapter` 属 M3/M4/M6）。
- 不实现 hook 阻塞等待/超时 fail-open 的运行时回路（属 M3/M4）。
- 不实现宠物窗、动画、气泡 UI、生成管线（属 M1/M2）。
- 不实现安装器写配置逻辑（属 M6）。
- `VibePetApp` 仅最小窗口，不接 `BridgeServer` 路由（属 M3）。

## Decisions

### D1：单一 Swift Package（SwiftPM）而非 Xcode project

- **选择**：用 `Package.swift` 定义四 target，`VibePetCore` 为 library，其余为 executable。
- **理由**：CI 友好（`swift build && swift test` 即可）、target 边界清晰、`VibePetCore` 可被 CLI 复用且不依赖 UI。符合技术方案 §1.1。
- **替代**：Xcode `.xcodeproj` —— 对 CI 与纯命令行验收不友好，且容易把 UI 依赖泄漏进 core，放弃。
- **注意**：`VibePetApp` 作为 SwiftPM executable 运行最小 SwiftUI/AppKit 窗口；app bundle 打包（签名/公证）留到 M6，不在 M0 范围。

### D2：`BubbleContent` 用 tagged enum + 手写 Codable

- **选择**：`BubbleContent` 为四 case enum，采用 discriminator 字段（如 `type` + payload）的手写 `Codable`，确保跨语言/跨版本稳定。`ActionPreview`、`BridgeResponse`、`ApprovalDecision` 同理。
- **理由**：Swift 自动合成 enum Codable 的 JSON 形态较隐晦且不稳定；hook ↔ App 是跨进程协议，需要明确、可固化为 fixture 的线格式（§3.2、§8.1）。
- **替代**：依赖编译器自动合成 —— 形态不可控、难写 fixture，放弃。
- **测试**：每个 case 编解码往返断言（§8.1 第 1 条），`needsResponse` 行为单测。

### D3：socket 传输用 POSIX/Network 原生实现，clean-room

- **选择**：`SocketPath` 负责路径与权限（目录 0700、套接字 0600）；`BridgeServer`/`BridgeClient` 实现 `AF_UNIX` + newline-delimited JSON 读写。优先用 Foundation/Network 原生 API，凭官方文档独立编写。
- **理由**：满足 §3.1 权限与行分隔约定；§11 要求不复用 open-vibe-island 源码——socket 协议属高风险模块，先写自有接口/测试再实现。
- **替代**：引入第三方 socket 库 —— 增加许可证核查与依赖，M0 不需要，放弃。
- **风险点**：残留 socket 导致 `bind` 失败 → 启动时 `unlink` 重建（§7）；连接失败返回明确 typed error（为后续 fail-open 打基础）。

### D4：模型层 UI 无关，全部放 `VibePetCore`

- **选择**：所有 Bridge 模型、`ToolAdapter`、`ConfigStore`、`AppConfig` 都在 `VibePetCore`，不 import AppKit/SwiftUI。
- **理由**：`VibePetHooks`/`VibePetSetup` 是 CLI，需复用 core 且不能拖入 UI；保证单测无 UI 依赖（§8.1）。
- **`EdgeInsets` 注意**：`PetAsset.boundingInset` 在技术方案里写作 `EdgeInsets`（SwiftUI 类型）。M0 不涉及 `PetAsset`（属 M1），但 `AppConfig` 的宠物位置等字段必须用 UI 无关类型（如自定义 `struct` 或 `CGRect`/`Double`），避免把 SwiftUI 拉进 core。

### D5：`ConfigStore` 缺文件返回默认值，不抛错

- **选择**：读路径不存在 → 返回 `AppConfig.default`；写入采用原子写（写临时文件再 rename）。
- **理由**：首启无配置是正常态（§6、§7 可靠性原则——不因缺配置阻塞）。
- **替代**：缺文件抛错由调用方兜底 —— 调用方分散处理易漏，放弃。

## Risks / Trade-offs

- **[socket 实现近似改写 open-vibe-island 源码（版权风险）]** → 按 §11：socket 协议为高风险模块，先写自有接口设计与测试 fixture，再凭官方 POSIX/Network 文档实现；PR 附官方文档链接，不以 open-island 代码作证据；优先由未读其源码者复核 diff。
- **[手写 Codext discriminator 与未来工具事件 schema 不一致]** → M0 只固化**内部**归一化模型线格式；具体工具事件解析（M3+）以官方样例 fixture 校验，二者解耦，互不影响。
- **[Swift 6 严格并发导致 `Sendable` 约束编译报错]** → 所有模型设计为值类型且 `Sendable`；`BridgeServer`/`BridgeClient` 的可变状态用 actor 或串行队列隔离。
- **[`VibePetApp` 作为 SwiftPM executable 跑 AppKit 窗口的生命周期问题]** → M0 仅需"能空跑起一个最小窗口、不崩"，用 `NSApplication` + `NSWindow` 最小骨架即可；完整 app bundle/签名留 M6。
- **[Application Support 目录写入副作用污染测试]** → socket/config 测试用临时目录注入路径（`SocketPath`/`ConfigStore` 接受可注入根路径），避免污染真实用户目录。

## Migration Plan

属新建项目，无存量迁移。落地顺序遵循任务级依赖：M0-1（骨架）→ M0-2（信封/气泡模型）→ M0-3（响应模型）→ {M0-4（adapter 协议）、M0-5（socket）}（均依赖 M0-2/M0-3）；M0-6（ConfigStore）仅依赖 M0-1，可与 M0-2~M0-5 并行。回滚＝删除新增 target 文件，无外部系统影响。

## Open Questions

- `BridgeServer`/`BridgeClient` 底层选 `Network.framework`（`NWListener`/`NWConnection`，需确认其对 `AF_UNIX` 的支持度）还是直接 POSIX `socket()/bind()/accept()`？倾向 POSIX 以获得对 newline 分帧与权限的精确控制，落码时据官方文档定夺。
- `AppConfig` 字段的确切集合与默认值（决策超时默认 20s、生成器默认 `local-cutout`）以 §6 为准，实现时若发现 M1/M2 需要更多字段，按"缺字段走默认"的向后兼容方式增补，不破坏既有 `config.json`。
