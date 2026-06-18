## Context

M0 交付了 `VibePetCore` 的数据模型、`ConfigStore`/`AppConfig` 与 Bridge 基础设施；M1 交付了离线生成管线 `GenerationService.generate(from:)`、`PetAssetStore` 与 `PetAsset`（含 `layers`）。M2 第一次引入 `VibePetApp` 的 AppKit/SwiftUI 代码，把这些 Core 能力组合成"活在桌面上的宠物"。

关键约束（项目守则 + 技术方案）：

- `VibePetCore` 必须保持 UI 无关——不得 import AppKit/SwiftUI。M2 的窗口、视图、菜单、面板都在 `VibePetApp`，但其中**可单测的纯逻辑**（吸附/clamp 几何、导入状态机、onboarding 标记）要能脱离 UI 验证。
- 透明浮动窗口的"按区域鼠标穿透"是 macOS 上的经典难点：既要让透明处点击穿透到桌面/其它窗口，又要让宠物本体可拖动、可点击。
- M2 只跑通宠物状态机的 `idle`/`greet` 子集；`notify`/`decide` 是 M3/M4 的事，本里程碑不引入气泡（`SpeechBubble`）。
- M2-6 的"第③步安装 hooks"在 M6 才接入，本里程碑仅占位。

## Goals / Non-Goals

**Goals:**

- 宠物以透明、无边框、悬浮所有 Space 的窗口常驻桌面，透明区域鼠标穿透、本体可交互（120×120pt）。
- 基于 `NSScreen.main.visibleFrame` 的定位、自由拖动、软吸附贴边、主屏 clamp 与位置持久化（启动时按当前 `visibleFrame` clamp 回）。
- 宠物视图加载活动 `PetAsset` 并播放待机呼吸/晃动、可选眨眼、打招呼动画，遵守 Reduce Motion。
- 菜单栏入口（显示/隐藏、切换宠物、导入、设置、退出）正确接线。
- 导入面板把 M1 管线接到用户操作：导入即抠图、进度驱动、棋盘格预览+命名、确认落盘并激活，错误不留半成品。
- 首启 onboarding（欢迎→生成宠物）仅出现一次，标记持久化到 `AppConfig`。

**Non-Goals:**

- 不实现气泡（`SpeechBubble`）、不引入 `notify`/`decide` 状态——留 M3/M4。
- 不实现多屏放置/跨屏位置记忆（MVP 仅主屏，已在 spec 中声明 clamp 进主屏）。
- 不实现设置页完整功能与 onboarding 第③步（安装 hooks）——留 M6；M2 仅"打开设置"入口与占位步。
- 不改动 M1 生成管线/存储的行为，只消费其 API。
- 不在 `VibePetCore` 引入任何 AppKit/SwiftUI 依赖。

## Decisions

### D1. 窗口承载：`NSWindow` + `NSHostingView`，按区域控制 `ignoresMouseEvents`

无边框透明 `NSWindow`（`styleMask=.borderless`、`isOpaque=false`、`backgroundColor=.clear`、`level=.floating`、`collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]`），内容用 SwiftUI 经 `NSHostingView` 承载。窗口本身覆盖宠物精灵框，**透明像素的点击穿透**靠 hit-test：精灵不透明区命中→宠物响应；透明区→穿透。

- 方案选择：相比"让整个窗口 `ignoresMouseEvents=true`"（那样宠物也不可拖），采用**按区域/按需切换** `ignoresMouseEvents` 或重写 hit-test，使透明处穿透、本体可交互。具体实现以"宠物本体矩形/alpha 命中"近似（MVP 用本体 bounding 区域即可，精确到 alpha 留作打磨）。
- 拒绝：`NSPanel.nonactivatingPanel` 作为主载体——MVP 用 `NSWindow` 足够；面板形态留给导入/设置这类模态 UI。

### D2. 定位/吸附几何下沉为纯值类型 `ScreenSnap`

把"给定宠物 bounding rect 与屏幕 `visibleFrame` → 计算默认落点 / 吸附后落点 / clamp 落点"抽成不依赖 AppKit 的纯函数（输入输出用 `CGRect`/`CGPoint`，来自 CoreGraphics 而非 AppKit/SwiftUI），放在可被 `VibePetCoreTests` 调用的位置。

- 这样首启落点（右缘内缩 24、贴底）、`mouseUp` 吸附（最近边 <40pt → 内缩 8pt、保留沿边坐标）、clamp 进 `visibleFrame` 都能单测，符合"可测逻辑脱离 UI"。
- `PetDragController`（AppKit）只负责把鼠标事件转成 rect 调用 `ScreenSnap`，并把结果写回窗口 frame 与 `ConfigStore`。
- 注意：`CGRect`/`CGPoint` 来自 CoreGraphics，是 UI 无关的，可安全用于 Core 测试；规避 SwiftUI `EdgeInsets`/AppKit `NSEdgeInsets` 等专有类型（与 M1 `PetAsset.boundingInset` 同一守则）。

### D3. 位置坐标语义：存"沿边锚定"而非绝对像素

`config.json` 存的位置在 `visibleFrame` 变化时要能 clamp 回。MVP 直接存 clamp 后的位置点（`AppConfig` 既有 pet position 字段），启动时若 `NSScreen.main.visibleFrame` 与上次不同则再过一遍 `ScreenSnap.clamp`。沿边滑动只影响拖动时的落点计算，不需要额外的"边+偏移"编码（MVP 简化）。

- 拒绝：引入"枚举边 + 沿边比例"的持久化模型——MVP 不必要的复杂度；clamp 已能覆盖分辨率变化场景。

### D4. 导入面板状态机放在 `PetImportViewModel`（`ObservableObject`），转移逻辑可单测

`PetImportPanel`（SwiftUI 视图）只渲染；`PetImportViewModel` 持有 `enum State { idle, generating, result, placed, error }` 与转移方法。生成走 `GenerationService.generate(from:)`，`progress` 回调更新 `generating` 进度。`result→placed` 调 `PetAssetStore` 写入并 set `config.activePetID`。

- 状态机转移（含 `generating→error` on throw、`error→generating` 重试、不产生半成品）以 ViewModel 状态为断言点单测。失败路径"不留半成品"靠：只有成功拿到最终 `PetAsset` 才调用 `PetAssetStore` 写入；失败时不写。
- 进度回调 `@MainActor` 更新，避免跨线程 UI 更新问题。

### D5. onboarding 标记落在 `AppConfig`，默认 `false` 保证向后兼容

`AppConfig` 新增 `hasCompletedOnboarding: Bool`（或等价命名），`Codable` 默认值 `false`，使 M0/M1 已写出的 `config.json`（无此字段）解码不报错且视为未完成。`OnboardingFlow` 在 App 启动时读该标记：未完成→走 欢迎→生成（复用 `PetImportPanel`）→置位并持久化；已完成→直接显示桌面宠物。

- 默认值通过自定义 `init(from:)` 或字段默认值实现（`decodeIfPresent ?? false`），与现有 `app-configuration` 的"missing file → default config"行为一致。
- 第③步占位：onboarding UI 留一屏 placeholder，不阻塞完成；M6 接 `VibePetSetup`。

### D6. 菜单栏 `StatusItemController` 直接接线现有协作对象

`NSStatusItem` 菜单各项调用已有控制器：show/hide 切窗口可见性、switch pet 改 `activePetID` 并刷新 `PetView`、import 弹 `PetImportPanel`、settings 打开设置窗口（M2 仅入口，内容 M6）、quit 终止。

## Risks / Trade-offs

- **透明窗口的精确 alpha 穿透较难** → MVP 以宠物本体 bounding 区域近似 hit-test（本体内响应、本体外穿透），像素级 alpha 命中留作 M6 打磨；spec 的穿透场景以"本体外透明区穿透、本体响应"为验收口径，不要求像素级精确。
- **`NSScreen.main.visibleFrame` 在多屏/分辨率切换下变化** → 启动与 `mouseUp` 都过一遍 `ScreenSnap.clamp`；多屏放置显式列为 Non-Goal，spec 声明 clamp 进主屏。
- **AppKit/SwiftUI UI 难以在 SwiftPM 无头 CI 上单测** → 把可测逻辑（`ScreenSnap` 几何、`PetImportViewModel` 状态机、`AppConfig` Codable）下沉为无 UI 依赖的单元测试；窗口/动画/菜单的视觉行为靠手动验收，不强求自动化 UI 测试。
- **进度回调跨线程更新 UI** → `progress` 闭包在 `@MainActor` 派发，ViewModel 状态变更走主线程。
- **新增 `AppConfig` 字段破坏既有 config** → 字段默认 `false` + `decodeIfPresent`，并加"legacy config 解码"单测覆盖向后兼容。
- **Reduce Motion 覆盖面** → 集中在动画入口判断 `accessibilityReduceMotion`，统一切到淡入淡出，避免逐处遗漏。

## Migration Plan

- 纯增量、无破坏性数据迁移。`AppConfig` 仅新增可选语义字段（默认 `false`），既有 `config.json` 自动兼容。
- 部署即随 App 二进制；回滚为还原代码即可，磁盘上 `config.json` 多出的 `hasCompletedOnboarding` 字段对旧版本无害（旧版本忽略未知字段或按其解码策略处理）。
- 验证顺序：先 `ScreenSnap`/`PetImportViewModel`/`AppConfig` 单测 `swift test`，再 `swift run VibePetApp` 手动走 首启 onboarding → 导入生成 → 拖动吸附 → 菜单项。

## Open Questions

- 透明窗口 hit-test 是否需要像素级 alpha 命中，还是本体 bounding 近似即可满足 US-2 体验？（MVP 倾向 bounding 近似，留待手动验收确认。）
- "切换宠物"菜单在有多个已存宠物时的列举/排序细节（依赖 `PetAssetStore.list()`），UI 呈现方式待实现时定。
- onboarding 第③步占位的具体文案与最小视觉，M6 接入前以 placeholder 为准。
