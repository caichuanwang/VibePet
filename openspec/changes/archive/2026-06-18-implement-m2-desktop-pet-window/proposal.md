## Why

M0 交付了工程骨架与数据模型，M1 交付了脱离 UI 的本地生成管线与素材存储——但宠物还没有"出现在桌面上"。里程碑 M2 是产品第一次有可见形态：宠物**透明浮动在桌面**、会呼吸/晃动/打招呼、可拖动并软吸附到屏幕边缘、有菜单栏入口，并通过一个紧凑的导入面板把 M1 的生成管线接到用户操作上。它对应 PRD US-1（生成宠物）/ US-2（宠物常驻桌面）/ US-0①②（首启欢迎与生成），是后续 M3 通知气泡、M4 审批气泡得以"长在宠物头顶"的前置载体。

本次变更覆盖技术方案 §5.1 / §5.1.1 / §5.2(idle/greet 子集) / §5.4 / §5.5 / §2.1(待机动画)，以及任务拆解 M2-1 ~ M2-6 的全部内容。

## What Changes

- 新增透明浮动 `NSWindow`（`VibePetApp/Window`）：无边框、`isOpaque=false`、`backgroundColor=.clear`、`level=.floating`、`collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary]`，透明区域鼠标穿透、仅宠物本体命中响应，默认精灵框 120×120pt（§5.1）。
- 新增宠物定位与软吸附：基于 `NSScreen.main.visibleFrame` 定位，首启落右缘内缩 24pt、贴底；自由拖动后 `mouseUp` 最近边距 < 40pt 则动画吸附（内缩 8pt）并保留沿边坐标；位置始终 clamp 进 `visibleFrame`，存入 `config.json`，启动时 `visibleFrame` 变化则 clamp 回（§5.1.1）。
- 新增 SwiftUI 宠物视图与动画（`VibePetApp/Pet`）：加载 `PetAsset` 精灵，待机呼吸（squash/stretch）+ 轻微晃动，`layers` 提供时叠加眨眼、否则跳过，打招呼动画；遵守"减弱动态效果"（Reduce Motion）改用淡入淡出（§2.1 末 / §5.3 通用）。
- 新增菜单栏 `NSStatusItem`（`VibePetApp/MenuBar`）：显示/隐藏宠物、切换宠物、导入新照片、打开设置、退出（§5.4）。
- 新增导入→生成面板 `PetImportPanel`（`VibePetApp/Import`）：单一紧凑面板，状态机 `idle→generating→result→placed`（错误转 `error`）；接受拖拽/选择 JPG/PNG/HEIC，**导入即自动抠图**（无独立生成按钮），`generating` 由 `progress` 回调驱动进度，`result` 棋盘格预览透明精灵 + 可选命名，确认后写入 `PetAssetStore` 与 `config.activePetID`、宠物落右下角进入待机，`error`（如 `.noSubject`）给可读提示且不产生半成品资源（§5.5 / §7）。
- 新增首启 Onboarding 骨架（`VibePetApp/Onboarding`）：首启依次 欢迎 → 生成宠物（复用 `PetImportPanel`），仅首启出现，完成后宠物落桌面进入待机；第③步（安装 hooks）留占位、M6 接入（US-0①②）。
- 修改 `app-configuration`：`AppConfig` 增加"首启/onboarding 已完成"标记，使 onboarding 仅首启出现一次，并随 `ConfigStore` 持久化。

## Capabilities

### New Capabilities
- `desktop-pet-window`: 宠物常驻桌面的透明浮动窗口——无边框透明、悬浮所有 Space、按区域鼠标穿透、默认 120×120pt；以及基于 `visibleFrame` 的定位、自由拖动、软吸附贴边、主屏 clamp 与位置持久化。
- `pet-view-animation`: 宠物 SwiftUI 视图加载 `PetAsset` 精灵并播放待机呼吸/晃动、可选眨眼叠加层、打招呼动画，并在 Reduce Motion 下降级为淡入淡出。
- `menu-bar`: 菜单栏 `NSStatusItem` 提供 显示/隐藏宠物、切换宠物、导入新照片、打开设置、退出 等入口并正确接线。
- `pet-import-panel`: 单一紧凑导入面板的 `idle→generating→result→placed/error` 状态机——导入即自动抠图、进度驱动、棋盘格预览与命名、确认落盘到 `PetAssetStore` 与 `config.activePetID`、错误不留半成品。
- `onboarding-flow`: 首启引导（欢迎 → 生成宠物，复用导入面板），仅首启出现一次，第③步安装 hooks 留占位。

### Modified Capabilities
- `app-configuration`: `AppConfig` 模型增加 onboarding 是否已完成的持久化标记（新增字段），用于驱动 `onboarding-flow` 仅首启出现；既有字段与读写行为不变。

## Impact

- **新增源码**：`VibePetApp/Window/`（`PetWindow.swift`、`PetWindowController.swift`、`PetDragController.swift`、`ScreenSnap.swift`）、`VibePetApp/Pet/`（`PetView.swift`、`PetAnimations.swift`）、`VibePetApp/MenuBar/StatusItemController.swift`、`VibePetApp/Import/`（`PetImportPanel.swift`、`PetImportViewModel.swift`）、`VibePetApp/Onboarding/OnboardingFlow.swift`。
- **修改源码**：`VibePetCore/Persistence/AppConfig.swift`（新增 onboarding 完成标记字段，默认值保证既有 `config.json` 向后兼容）。
- **新增测试**：`Tests/VibePetCoreTests/`（`ScreenSnap` 吸附/clamp 纯函数测试、`AppConfig` 新字段 Codable 往返与默认值测试、`PetImportViewModel` 状态机转移测试——均为不依赖 AppKit/SwiftUI 的可单测逻辑）。
- **复用 M0/M1**：`PetView` 消费 `PetAsset`/`PetAsset.layers`；`PetImportPanel` 调用 `GenerationService.generate(from:)` 与 `PetAssetStore`；窗口定位与 onboarding 标记读写 `ConfigStore`/`AppConfig`。
- **依赖**：AppKit / SwiftUI（仅 `VibePetApp`，不进入 `VibePetCore`）；无第三方依赖，全程不联网。
- **运行时副作用**：写入/更新 `~/Library/Application Support/VibePet/config.json`（宠物位置、activePetID、onboarding 标记）与 `pets/<uuid>/`（经 `PetAssetStore`）。
- **守则**：保持 `VibePetCore` 不 import AppKit/SwiftUI——可测的吸附/clamp 几何与状态机逻辑要么以纯值类型留在 Core，要么以无 UI 依赖的形式留在 App 并单测；位置/尺寸等跨界类型不得使用 SwiftUI/AppKit 专有类型。
- **下游解锁**：M3-2 `PetController` 状态机与 M3-3 气泡锚定直接复用本窗口的几何/象限信息与宠物视图载体。
