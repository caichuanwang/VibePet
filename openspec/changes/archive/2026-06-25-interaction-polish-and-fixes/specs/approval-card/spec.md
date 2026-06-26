## REMOVED Requirements

### Requirement: Approval countdown fails open

**Reason**: 0.3 移除 App 侧决策超时——审批一直挂起直到用户点击，不再有可视化倒计时或到点自动 `.defer`。最终 fail-open 兜底改由 CLI hook 自身的读超时承担（见 `hook-installer`、`pet-controller`）。

**Migration**: `ApprovalCard` 不再接收 `timeout` 参数，也不渲染倒计时；移除卡片内的倒计时计时器与到零 `.defer` 路径。仍由用户主动 Allow / Deny / Always-allow 或 dismissal（dismissal → `.defer`）解决；"Handle in terminal" 终端审批降级形态不受影响（仍跳转后 `.defer`）。等待中的"还有 N 个待处理"计数仍可保留展示。
