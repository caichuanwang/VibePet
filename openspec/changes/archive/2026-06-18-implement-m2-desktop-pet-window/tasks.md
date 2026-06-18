## 1. AppConfig onboarding 标记（前置，支撑 M2-3/M2-6）

- [x] 1.1 在 `VibePetCore/Persistence/AppConfig.swift` 给 `AppConfig` 增加 `hasCompletedOnboarding: Bool`，默认 `false`，用 `decodeIfPresent ?? false` 保证缺字段的旧 `config.json` 解码为未完成
- [x] 1.2 在 `Tests/VibePetCoreTests/` 加单测：新字段 Codable 往返、缺字段的 legacy config 解码为 `false`、默认配置中为 `false`
- [x] 1.3 运行 `swift test` 确认 `app-configuration` 既有测试与新测试全绿

## 2. M2-1 透明浮动 NSWindow

- [x] 2.1 新增 `VibePetApp/Window/PetWindow.swift`：无边框 `NSWindow`，`isOpaque=false`、`backgroundColor=.clear`、`level=.floating`、`collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]`，默认精灵框 120×120pt
- [x] 2.2 新增 `VibePetApp/Window/PetWindowController.swift`：用 `NSHostingView` 承载 SwiftUI 内容；实现按区域控制 `ignoresMouseEvents`/hit-test，使透明区点击穿透、宠物本体响应
- [x] 2.3 `swift run VibePetApp` 手动确认：窗口透明无边框、悬浮所有 Space、透明处可点穿到桌面、本体可命中 *(已人工验证 ✓；穿透改为逐像素 alpha 命中 `SpriteHitMask`，由 PetWindowController 鼠标监听驱动 ignoresMouseEvents，修复了 hitTest 内翻转导致的卡死)*

## 3. M2-2 宠物视图与待机/打招呼动画

- [x] 3.1 新增 `VibePetApp/Pet/PetView.swift`：加载活动 `PetAsset` 的 `primaryImageURL` 精灵并保留透明渲染
- [x] 3.2 新增 `VibePetApp/Pet/PetAnimations.swift`：待机呼吸（squash/stretch）+ 轻微晃动；`layers` 提供时叠加眨眼、否则跳过；打招呼动画（区别于待机）
- [x] 3.3 在动画入口判断 `accessibilityReduceMotion`，开启时改用淡入淡出替代弹跳/spring
- [x] 3.4 手动确认：待机有呼吸/晃动、无 `layers` 不眨眼也不报错、greet 播放打招呼、Reduce Motion 下降级为淡入淡出 *(已人工验证 ✓)*

## 4. M2-3 拖动、软吸附与位置持久化

- [x] 4.1 新增 `VibePetApp/Window/ScreenSnap.swift`：纯值类型（`CGRect`/`CGPoint`，不依赖 AppKit/SwiftUI）实现 默认落点（右缘内缩 24、贴底）、`mouseUp` 吸附（最近边 <40pt → 内缩 8pt、保留沿边坐标）、clamp 进 `visibleFrame`（实现位于 `VibePetCore/Geometry/ScreenSnap.swift`，App 侧经 `@_exported` 复用，确保可单测且 Core 无 UI 依赖）
- [x] 4.2 在 `Tests/VibePetCoreTests/` 加 `ScreenSnap` 纯函数单测：首启落点、吸附触发/不触发、沿边坐标保留、越界 clamp
- [x] 4.3 新增 `VibePetApp/Window/PetDragController.swift`：把鼠标拖动事件转 rect 调 `ScreenSnap`，`mouseUp` 动画吸附，结果写回窗口 frame 与 `ConfigStore`
- [x] 4.4 启动时读 `config` 位置并按当前 `NSScreen.main.visibleFrame` 过一遍 `ScreenSnap.clamp`（分辨率/缩放变化时回拉，`PetFrameResolver.initialFrame`）
- [x] 4.5 手动确认：拖到任意处、近边吸附内缩 8pt、远边不吸附、重启位置保留、改分辨率后 clamp 回 *(已人工验证 ✓)*

## 5. M2-4 菜单栏（NSStatusItem）

- [x] 5.1 新增 `VibePetApp/MenuBar/StatusItemController.swift`：`NSStatusItem` 菜单含 显示/隐藏宠物、切换宠物、导入新照片、打开设置、退出
- [x] 5.2 接线各项：show/hide 切窗口可见性、switch pet 改 `config.activePetID` 并刷新 `PetView`（列举走 `PetAssetStore.list()`）、import 弹 `PetImportPanel`、settings 打开设置入口（M2 仅入口）、quit 终止
- [x] 5.3 手动确认：每个菜单项行为正确 *(已人工验证 ✓)*

## 6. M2-5 导入→生成面板（PetImportPanel）

- [x] 6.1 新增 `VibePetApp/Import/PetImportViewModel.swift`：`ObservableObject`，包装已单测的 Core `PetImportStateMachine`（`idle/generating/result/placed/error`）；生成走 `GenerationService.generate(from:)`、`progress` 回调（`@MainActor`）更新进度
- [x] 6.2 失败路径：`generating` 抛 `GenError` → `error`（不写任何半成品资源——生成器抠图成功才落盘、`.noSubject` 在落盘前抛出）；`error→generating` 重试；落盘后 `place` 设 `config.activePetID`
- [x] 6.3 在 `Tests/VibePetCoreTests/` 加 `PetImportStateMachine` 状态机单测：happy-path 顺序、`generating→error`、重试、失败不记录可放置资源
- [x] 6.4 新增 `VibePetApp/Import/PetImportPanel.swift`：`idle` 拖拽/选择 JPG/PNG/HEIC 即自动抠图（无独立生成按钮）；`generating` 进度展示；`result` 棋盘格预览透明精灵 + 预填可选命名 + 「换一张」「放上桌面」；`placed` 关闭面板、宠物落右下角进入待机；`error` 可读提示 + 换一张/重试
- [x] 6.5 手动确认：导入即抠图、进度更新、result 预览/命名、确认落盘并激活、`.noSubject` 给可读错误且不留半成品 *(已人工验证 ✓)*

## 7. M2-6 首启 Onboarding 骨架

- [x] 7.1 新增 `VibePetApp/Onboarding/OnboardingFlow.swift`：首启依次 ①欢迎 → ②生成宠物（复用 `PetImportPanel`）；第③步安装 hooks 留 placeholder（不阻塞完成）
- [x] 7.2 启动读 `AppConfig.hasCompletedOnboarding`：未完成走 onboarding、完成后置位并持久化、已完成直接显示桌面宠物（`AppDelegate.applicationDidFinishLaunching`）
- [x] 7.3 手动确认：首启出现 欢迎→生成、完成后宠物落桌面进入待机、再次启动不再出现 onboarding *(已人工验证 ✓)*

## 8. 集成与验收

- [x] 8.1 运行 `swift build` 全 target 通过、`swift test`（`ScreenSnap`/`PetImportStateMachine`/`AppConfig` 等无 UI 单测）全绿（50 tests, 0 failures）
- [x] 8.2 `swift run VibePetApp` 端到端手动走查：首启 onboarding → 导入生成 → 宠物待机动画 → 拖动吸附/持久化 → 菜单项，确认 US-1/US-2/US-0①② 覆盖 *(已人工验证 ✓)*
- [x] 8.3 复核 `VibePetCore` 未 import AppKit/SwiftUI、跨界位置/尺寸类型未使用 SwiftUI/AppKit 专有类型（grep 确认 Core 无 UI import；几何用 CoreGraphics `CGRect`/`CGPoint`）
- [x] 8.4 `openspec validate implement-m2-desktop-pet-window` 通过
