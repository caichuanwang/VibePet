## Why

VibePet 当前只有文档（PRD、技术方案、任务拆解），没有任何可编译代码。里程碑 M0 是整个 MVP 的地基：先立起一个可 `swift build` / `swift test` 的工程骨架，并把后续所有里程碑都要复用的**归一化数据模型**与 **hook ↔ App 通信基础设施**就位。没有 M0，M1（生成管线）、M3（通知链路）、M4（审批闭环）等无法落地。

本次变更覆盖技术方案 §9/M0 与任务拆解 M0-1 ~ M0-6 的全部内容。

## What Changes

- 新建单一 Swift Package，划分四个 target：`VibePetCore`（library）、`VibePetApp` / `VibePetHooks` / `VibePetSetup`（executable），`VibePetApp` 能空跑一个最小窗口；`Tests/` 骨架就位，`swift build && swift test` 可运行（即便 test 暂空）。
- 在 `VibePetCore` 定义 Bridge 信封与气泡内容模型：`BridgeEnvelope` / `SourceInfo` / `ToolKind` / `BubbleContent`（`approval`/`question`/`completion`/`status` 四 case）及各 Content 结构（§3.2），`BubbleContent.needsResponse` 行为正确。
- 定义 Bridge 响应模型：`BridgeResponseEnvelope` / `BridgeResponse`（`approval`/`question`/`defer`）/ `ApprovalDecision` / `QuestionAnswer`，`requestId` 配对（§3.3）。
- 定义 `ToolAdapter` 协议（`tool` / `parseEvent(stdin:env:)` / `encodeResponse(_:for:)`，§4），可被 mock 实现并编译通过。
- 实现 Unix domain socket 收发基础设施：`BridgeServer` / `BridgeClient` / `SocketPath`，套接字位于 `~/Library/Application Support/VibePet/bridge.sock`（目录 0700、套接字 0600），完成一次 newline-delimited JSON 往返，App 启动清理并重建残留 socket（§3.1、§7）。
- 实现 `ConfigStore` 骨架：读写 `config.json`（活动宠物、启用工具、决策超时、生成器 ID、宠物位置等字段），文件不存在时返回默认配置（§6）。
- 全部上述模型与基础设施附带编解码/往返单元测试（§8.1 第 1、5 条的模型部分）。

## Capabilities

### New Capabilities
- `project-scaffold`: 单一 Swift Package 与四 target 的可编译/可单测工程骨架，含最小 App 窗口与测试目录。
- `bridge-protocol`: hook ↔ App 之间归一化的消息信封、气泡内容与回传响应数据模型及其 Codable 编解码契约。
- `tool-adapter`: 把各 AI 工具事件格式与决策回写差异封装到统一协议 `ToolAdapter` 的抽象层。
- `bridge-transport`: 基于 Unix domain socket 的本地进程间通信基础设施（服务端、客户端、路径与权限管理）。
- `app-configuration`: 应用配置的读写与默认值管理（`config.json` / `ConfigStore` / `AppConfig`）。

### Modified Capabilities
<!-- 无：这是项目首个里程碑，`openspec/specs/` 当前为空，不存在需要修改的既有 capability。 -->

## Impact

- **新增源码 target**：`VibePetCore/`（Bridge、Adapters、Persistence 子目录）、`VibePetApp/`、`VibePetHooks/`、`VibePetSetup/`、`Tests/`。
- **新增构建配置**：`Package.swift`（Swift 6.x、macOS 14+ 平台、四 target 与测试 target）。
- **新增运行时副作用**：在 `~/Library/Application Support/VibePet/` 下创建目录、`bridge.sock`、`config.json`（仅当前用户、0700/0600 权限）。
- **依赖**：纯 Apple 原生框架（Foundation / AppKit / SwiftUI / Network 或 POSIX socket）；本里程碑无第三方依赖。
- **下游解锁**：M1（生成管线）、M2（宠物窗）、M3（通知链路）均以本里程碑产出的模型、协议与 socket 基础设施为前置。
