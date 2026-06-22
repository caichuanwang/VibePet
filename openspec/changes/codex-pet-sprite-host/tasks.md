## 1. Spike（先钉死未知，再动手）

- [ ] 1.1 Inspect 一个真实 petdex 画廊宠物（如 `boba`）的 `pet.json`，确认是否带 states/frame durations 扩展字段 → 定 D4 是否真读声明（design Open Q1）
- [ ] 1.2 取 2–3 个画廊样本，核对行序是否都遵循官方 9 行约定（design Open Q2）
- [ ] 1.3 验证 `CGImageSource`/`ImageIO` 直接解码 `.webp` spritesheet 成功（trump 实测基线），确认无需第三方库（design D5）
- [ ] 1.4 评估每帧重建 `SpriteHitMask` 开销，定降采样粒度（design Open Q3）

## 2. Core — 资源模型与聚合读取（codex-pet-source）

- [ ] 2.1 把 `PetAsset` 从「UUID 单图」改为「Codex 文件夹引用」：`slug`/`displayName`/`source`/`folderURL`/`spritesheetURL` 等
- [ ] 2.2 写 `pet.json` 解析单测（fixture：合法宠物→期望 `PetAsset`；缺字段/网格不符→跳过+可读原因），再实现解析+校验（8×9×192×208）
- [ ] 2.3 写聚合读取单测（两根去重导入优先、共享目录缺失返回空、非法宠物跳过、旧 UUID 格式忽略不崩），再把 `PetAssetStore` 改为多根聚合读取器
- [ ] 2.4 共享 `~/.codex/pets/` 只读原地引用、不拷贝；导入目录路径沿用 `~/Library/Application Support/VibePet/pets/`
- [ ] 2.5 验证：`swift test` 通过该组单测

## 3. Core — 动画约定表与状态→行映射（sprite-animation）

- [ ] 3.1 内建 Codex 9 行约定表（绝对行号 + 每行有效列数 + per-frame durations，来自 `animation-rows.md`）
- [ ] 3.2 `PetVisualState` 定义并把 `review` 改名 `waiting`；映射表：idle=0 / waving=3 / failed=5 / waiting=6 / running=7（design D2/D3）
- [ ] 3.3 写状态→行映射单测（各 `SessionState` 聚合→期望 `PetVisualState`→期望绝对行号 + durations；pet.json 声明优先、缺失走内建表），再实现派生逻辑
- [ ] 3.4 验证：`swift test` 通过该组单测

## 4. Core — 切片与当前帧 alpha 命中

- [ ] 4.1 写切片单测（1536×1872 → 72 帧、按 (row,col) 取单元、尾部透明列识别），再实现网格切片（保持 Core UI 无关，输出 `CGImage` 帧）
- [ ] 4.2 把 `SpriteHitMask` 掩码源从单图改为「当前帧」，按 1.4 粒度降采样；写当前帧 alpha 命中单测（透明穿透/本体响应）
- [ ] 4.3 验证：`swift test` 通过该组单测

## 5. App — 精灵渲染器（替换伪动画）

- [ ] 5.1 新建 `SpriteSheetAnimator`：`@State frameIndex` + per-frame 异步步进循环（按 durations[i] sleep 推进、无限循环、只播有效列），观察 `frameIndex` 绘制对应帧（design D1）
- [ ] 5.2 Reduce Motion：开启时显示当前行第 0 帧静帧、不启动循环
- [ ] 5.3 改 `PetView`：删单图 `sprite`/呼吸摇摆眨眼，改为驱动 `SpriteSheetAnimator`；按目标高度（沿用 `spriteSide` 量级）等比缩放、高质量插值
- [ ] 5.4 命中掩码随 `frameIndex` 更新接到 `PetWindowSurface`/窗口命中链路

## 6. App — 控制器对接

- [ ] 6.1 `PetController`/`PetStateMachine` 对接新 `PetVisualState`（idle/running/waiting/waving/failed），打招呼/干净完成→waving、失败→failed 的瞬时态处理
- [ ] 6.2 子项目1 `SessionState` 未落地时，按现有事件派生临时 `PetVisualState`（idle/waiting/waving/failed，running 缺省）

## 7. 导入 — zip 为主 + 文件夹兼收（codex-pet-import）

- [ ] 7.1 写导入单测：标准 zip 落地、文件夹落地、单层包裹目录（`boba/pet.json`）容忍、缺文件/网格不符拒绝且不污染目录
- [ ] 7.2 实现：zip 解压到临时目录 → 向下定位含 `pet.json` 的层 → 校验网格 → 按 slug 拷入导入目录；文件夹走同一「定位→校验→拷入」路径
- [ ] 7.3 验证：`swift test` 通过该组单测（仅单测、不做真实冒烟）

## 8. UI — 挑宠物 / 空状态 / 切换 / 导入入口

- [ ] 8.1 Onboarding ②步「生成宠物」→「挑一个宠物」：列聚合宠物供选
- [ ] 8.2 空状态引导（平台中立文案：任意方式装进 `~/.codex/pets/` 或拖入；可「以后再说」）
- [ ] 8.3 设置页/菜单栏：「切换宠物」从聚合列表选；新增「导入宠物…（zip/文件夹，拖拽或选取）」

## 9. 删除抠图管线 + 护栏

- [ ] 9.1 删除 `Generation/`（PetGenerator/LocalCutoutGenerator/GenerationService/PetImportStateMachine）、旧 `PetImportPanel`+ViewModel、`PetAnimations` 单图部分、`Tools/CutoutBenchmark`、`Tests/Fixtures/photos/`
- [ ] 9.2 删除旧 spec：`openspec/specs/{cutout-quality-benchmark,pet-generation,pet-generator-protocol,pet-asset-store,pet-import-panel,pet-view-animation}`（按实际存在为准）
- [ ] 9.3 改写 `CLAUDE.md` 护栏：抠图/CutoutBenchmark 条款 → 「Codex 宠物宿主、本地优先、无网络生成、改 SpriteSheetAnimator/PetAssetStore 时跑 swift test」
- [ ] 9.4 清理 `SpriteHitMask` 保留确认、`ImageLoading` 视复用精简，移除因删除产生的悬挂引用

## 10. 回归验证

- [ ] 10.1 `swift build` 通过、无悬挂引用
- [ ] 10.2 `swift test` 全绿（偶发 SIGPIPE 非回归，可 `--filter` 重跑）
- [ ] 10.3 `swift package describe --type json` 确认 CutoutBenchmark 目标已移除、产物一致
- [ ] 10.4 手测要点（仅观察、写入仍仅命中真实目录故不做自动冒烟）：装一个 Codex 宠物→VibePet 自动出现并逐帧动；切状态观察行切换；Reduce Motion 静帧；空状态引导可读
