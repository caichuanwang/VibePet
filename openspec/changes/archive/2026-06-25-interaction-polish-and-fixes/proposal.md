## Why

0.3 的会话面板（`session-dashboard-panel`）落地后，余下四类打磨与修正决定了体验是否"简洁可信"：审批/问答卡片仍是早期裸气泡观感、Codex 在工具执行阶段缺少状态心跳、决策强制倒计时与产品"等用户决定"的意图冲突、Claude 多主题提问的提交校验存在丢答 bug。这一批集中收口，使决策链路与界面表现达到 0.3 的发布标准。

## What Changes

- **C 界面优化**：把分散的卡片样式收敛到统一的暗色设计令牌（`BubbleTheme`），审批卡 / 问答卡 / 通知气泡按统一的背景层、卡片层、圆角、状态色重绘；宠物窗口增加常驻的状态指示小圆点（绿=运行中 / 橙=待处理 / 灰=空闲）。
- **D Codex 工具心跳**：Codex 安装的受管 hook 增加 `PostToolUse`，适配器把它映射为 `activityUpdated`，使"运行中"会话在每次工具执行后刷新摘要与时间戳，消除状态陈旧。**需要用户重装一次 hook**。
- **E 移除决策超时**：审批 / 问答不再有 App 侧倒计时与到点自动 `.defer`；决策一直挂起直到用户点击。设置页删除"决策超时"项，配置不再使用 `decisionTimeoutSeconds`。CLI hook 自身的读超时仍作为最终 fail-open 兜底，**不移除**。
- **F Claude 多主题提交修正**：问答卡提交校验由"至少一个问题已答"改为"每个问题都已答"（freeform 选项需非空文本），与 Claude `AskUserQuestion` 的多主题语义一致，杜绝丢答提交。

## Capabilities

### New Capabilities
<!-- 本批为打磨与修正，不引入新 capability。 -->

### Modified Capabilities

- `desktop-pet-window`: 宠物窗口新增常驻状态指示小圆点需求（C 唯一的 spec 级可观察变化）。
- `approval-card`: 移除可视化倒计时与到点自动 `.defer`（E）。
- `question-card`: 移除倒计时；提交校验改为全部问题已答（E、F）。
- `pet-controller`: 移除 App 侧决策超时，决策挂起至用户响应；dismissal 仍 `.defer`，保留 hook 侧兜底（E）。
- `codex-adapter`: `PostToolUse` → `activityUpdated` 状态心跳（D）。
- `hook-installer`: Codex 受管 hook 集合加入 `PostToolUse`；tool 侧 timeout 成为唯一 fail-open 兜底（D、E）。
- `settings-page`: 移除"决策超时"设置项（E）。
- `app-configuration`: 弃用 `decisionTimeoutSeconds`（容忍旧配置解码，但不再读取/写入）（E）。

> C 的暗色令牌统一与卡片重绘属实现细节（无 spec 行为变化），在 design.md / tasks.md 中跟踪，不单列 capability。

## Impact

- **代码**：`VibePetApp/Bubble/`（`BubbleTheme`、`ApprovalCard`、`QuestionCard`、`SpeechBubble`）、`VibePetApp/Pet/PetController.swift`、`VibePetApp/Window/`（状态点叠加）、`VibePetApp/Settings/SettingsView.swift`、`VibePetCore/Adapters/CodexAdapter.swift`、`VibePetCore/Install/CodexConfigWriter.swift`、`VibePetCore/Persistence/AppConfig.swift`。
- **依赖关系**：与 `session-dashboard-panel` 同时在 `desktop-pet-window` / `pet-controller` 上做 delta（不同需求项，互不覆盖）；C 的令牌统一以工作树已存在的 dashboard 令牌为基础继续收敛。
- **安装器**：Codex `hooks.json` 受管组发生变化，已安装用户需在设置页 / onboarding 重装一次 hook 才能获得 `PostToolUse` 心跳。
- **守线**：fail-open 红线不破——移除的是 App 侧倒计时，CLI hook 读超时仍兜底；`PetController` 决策续延仍单一所有权。
- **测试**：`swift test`（涉及 `CodexAdapter`、`CodexConfigWriter`、`PetController`、问答卡校验）。
