# VibePet 发布检查清单（M6-7）

> 状态：**签名/公证延后**（M6 范围决定：APP 签名放在后面）。本清单为发布动作的占位，
> 代码侧（适配/安装器/设置页/主题/错误统一）已在 M6 完成；下列项在单独的发布动作中执行。

## 代码与测试（M6 内已完成）
- [x] `swift build` 通过、`swift test` 全绿
- [x] CodexAdapter（PermissionRequest/Stop/notify、approval 回写、提问降级）
- [x] 安装器（二进制稳定路径、manifest install/uninstall/status、Claude+Codex 写入、Codex trust 三态）
- [x] 设置页 / onboarding③ / `ErrorPresenter` / `BubbleTheme`（跟随明暗）

## 发布动作（延后，需人工/环境）
- [ ] 准备 Apple Developer ID Application 证书与 `notarytool` keychain profile
- [ ] 打包 `VibePet.app`（含 `VibePetHooks` / `VibePetSetup` 辅助二进制）
- [ ] 运行签名 + 公证（见 `Scripts/notarize.sh` 大纲）→ `stapler staple`
- [ ] `codesign --verify --deep --strict` 与 `spctl -a -vv` 校验通过

## KPI 真机验收（M6-10，需真实会话）
- [ ] 端到端审批闭环（真实 Claude Code 会话）：气泡 ≤500ms、允许/拒绝真实回传
- [ ] Fail-open 100%：App 未运行 ≤2s `defer`；无响应到点 `defer`
- [ ] Codex 审批回路（真实 Codex 会话）+ 提问降级提示
- [ ] Codex `installedNeedsTrust → trustedActive`（收到真实 Codex 事件后）
- [x] 抠图/照片基准 KPI（M1-5 已测通过，引用既有结论，不重复跑）
