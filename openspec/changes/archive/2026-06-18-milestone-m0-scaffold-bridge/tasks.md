## 1. M0-1 · Swift Package 与四 target 骨架

- [x] 1.1 编写 `Package.swift`：platforms macOS 14+、Swift 6 tools 版本；声明 `VibePetCore`（library）、`VibePetApp`/`VibePetHooks`/`VibePetSetup`（executable）四 target 及对应测试 target，依赖关系为三 executable 均依赖 `VibePetCore`
- [x] 1.2 建目录骨架：`VibePetCore/`（含 `Bridge/`、`Adapters/`、`Persistence/` 子目录占位）、`VibePetApp/`、`VibePetHooks/`、`VibePetSetup/`、`Tests/VibePetCoreTests/`
- [x] 1.3 写各 executable 入口：`VibePetHooks/main.swift`、`VibePetSetup/main.swift`（最小可执行占位）；`VibePetApp/VibePetApp.swift` 用 `NSApplication`+`NSWindow` 空跑一个最小窗口、不崩
- [x] 1.4 在 `Tests/VibePetCoreTests/` 放一个最小测试用例，确保 `swift test` 在空套件下退出码 0
- [x] 1.5 验证 `swift build && swift test` 全绿，四 target 均生成产物（验收：M0-1）

## 2. M0-2 · Bridge 信封与气泡内容模型

- [x] 2.1 在 `VibePetCore/Bridge/BridgeEnvelope.swift` 定义 `BridgeEnvelope`、`SourceInfo`、`ToolKind`（`claudeCode`/`codex`），均 `Codable`+`Sendable`
- [x] 2.2 定义 `BubbleContent` tagged enum 四 case（`approval`/`question`/`completion`/`status`）及手写 `Codable`（带 discriminator）；实现 `needsResponse`（approval/question→true，completion/status→false）
- [x] 2.3 定义 Content 结构：`ApprovalContent`、`QuestionContent`、`QuestionItem`、`QuestionOption`、`CompletionContent`、`StatusContent`，以及 `ActionPreview`（command/fileChange/fileRead/network/generic）、`AlwaysAllowOption`、`RiskLevel`（low/medium/high），全部 `Codable`+`Sendable`（按 §3.2）
- [x] 2.4 在 `Tests/VibePetCoreTests/BridgeEnvelopeCodecTests.swift` 写编解码往返单测：四种 `content` case 各往返一次、`ActionPreview` 各变体往返、`needsResponse` 行为断言（验收：M0-2、§8.1 第 1 条）

## 3. M0-3 · Bridge 响应模型

- [x] 3.1 在 `VibePetCore/Bridge/BridgeResponse.swift` 定义 `BridgeResponseEnvelope`（`requestId`+`response`）、`BridgeResponse`（`approval`/`question`/`defer`）、`ApprovalDecision`（`allowOnce`/`allowAlways(scopeHint:)`/`deny(reason:)`）、`QuestionAnswer`（`answers`/`freeform`），手写 `Codable`，全部 `Sendable`
- [x] 3.2 在 `Tests/VibePetCoreTests/BridgeResponseCodecTests.swift` 写往返单测：各 `BridgeResponse` case（含 `defer`、`deny` reason、`allowAlways` scopeHint）往返，`requestId` 配对字段保真（验收：M0-3）

## 4. M0-4 · ToolAdapter 协议

- [x] 4.1 在 `VibePetCore/Adapters/ToolAdapter.swift` 定义 `ToolAdapter` 协议（`Sendable`）：`var tool: ToolKind`、`parseEvent(stdin:env:) throws -> BridgeEnvelope?`、`encodeResponse(_:for:) -> Data`，签名与 M0-2/M0-3 模型对齐
- [x] 4.2 在 `Tests/VibePetCoreTests/ToolAdapterMockTests.swift` 写 mock 实现并断言：可编译、`parseEvent` 返回 `BridgeEnvelope`、未识别事件返回 `nil`、`encodeResponse` 返回 `Data`（验收：M0-4）

## 5. M0-5 · Unix socket 收发基础设施

- [x] 5.1 在 `VibePetCore/Bridge/SocketPath.swift` 实现 socket 路径解析（`~/Library/Application Support/VibePet/bridge.sock`），创建目录 0700、套接字 0600；支持可注入根路径以便测试
- [x] 5.2 在 `VibePetCore/Bridge/BridgeServer.swift` 实现监听/接受连接、newline-delimited JSON 解码；启动时 `unlink` 清理并重建残留 socket（§7）；可变状态用 actor/串行队列隔离（Swift 6 并发）
- [x] 5.3 在 `VibePetCore/Bridge/BridgeClient.swift` 实现连接 + 一次 newline-delimited JSON 往返；连接失败返回明确 typed error
- [x] 5.4 在 `Tests/VibePetCoreTests/BridgeRoundTripTests.swift` 写本地往返集成测试：临时目录注入路径，断言一次 envelope→response 往返成功、残留 socket 被清理、无服务端时连接返回错误（验收：M0-5、§8.1 socket 部分）

## 6. M0-6 · ConfigStore 骨架

- [x] 6.1 在 `VibePetCore/Persistence/AppConfig.swift` 定义 `AppConfig`（`activePetID`、启用工具、决策超时[默认 20s]、生成器 ID[默认 `local-cutout`]、宠物位置等，UI 无关类型），`Codable`，提供 `default`
- [x] 6.2 在 `VibePetCore/Persistence/ConfigStore.swift` 实现读写 `config.json`（原子写）；文件不存在返回默认配置；支持可注入根路径以便测试
- [x] 6.3 在 `Tests/VibePetCoreTests/ConfigStoreTests.swift` 写单测：缺文件返回默认、写后读往返一致、`AppConfig` Codable 往返（验收：M0-6）

## 7. 里程碑收尾验收

- [x] 7.1 运行全量 `swift build && swift test` 全绿
- [x] 7.2 核对 M0 退出标准：四种 `content` case 编解码往返全绿、`BridgeClient`↔`BridgeServer` 完成一次 newline-delimited JSON 往返（技术方案 §9/M0）
