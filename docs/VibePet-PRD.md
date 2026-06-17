# VibePet 产品需求文档（PRD）

> 版本：v0.1（MVP）
> 日期：2026-06-17
> 状态：已通过头脑风暴评审，待实现
> 平台：macOS 14+（Sonoma 及以上）

---

## 1. 执行摘要（Executive Summary）

### 问题陈述
开发者在使用 vibe coding 工具（Claude Code、Codex 等）时，AI Agent 经常需要人工决策（确认权限、批准命令执行、批准文件修改）。当前这些"需要你拍板"的时刻只发生在终端里，开发者一旦切换窗口就容易错过，导致 Agent 空等、心流被打断、需要频繁切回终端查看。

### 解决方案
VibePet 是一个 macOS 原生桌面宠物应用。用户上传自己宠物或名人的照片，本地生成一个会动的 2D 桌面宠物。宠物除日常陪伴（打招呼、待机动画）外，会注册进 vibe coding 工具的 hooks：当 Agent 需要人工决策时，宠物在桌面气泡里直接给出"允许 / 拒绝"按钮，**点击即实时回传决策，无需切回终端**——把"提醒"和"决策"合并到一个可爱的桌面入口。

### 成功标准（可度量 KPI）
| 指标 | 目标值 |
|---|---|
| 端到端闭环 | 上传照片 → 生成精灵 → 桌面显示 → Claude Code 触发 `PreToolUse` → 宠物气泡出现 → 点击"拒绝" → 工具调用被真实取消。全链路 Demo 成功跑通。 |
| 决策回路延迟 | 工具触发到宠物气泡出现 ≤ 500ms（本地 Unix socket）。 |
| 本地抠图耗时 | Apple Silicon 上 P50 ≤ 3s，P95 ≤ 8s。 |
| 抠图主观可用率 | 20 张"主体清晰"测试照片中，边缘质量可接受的 ≥ 80%。 |
| Fail-open 可靠性 | App 未运行时，hook 在 ≤ 2s 内退出且不阻塞 Agent，成功率 100%。 |

---

## 2. 用户体验与功能（User Experience & Functionality）

### 2.1 用户画像（Personas）

**主画像 —— "心流开发者" Leo**
重度使用 Claude Code / Codex 的独立开发者或工程师。经常同时开多个终端跑 Agent，讨厌频繁切窗口查看"Agent 卡在哪了"。希望有一个不打扰、但关键时刻能一眼看到并一键处理的入口。喜欢有点个性化、好玩的工具。

**次画像 —— "尝鲜玩家" Mia**
对 AI 桌宠、个性化装扮感兴趣的用户。核心动机是"把我家猫/我喜欢的角色变成桌面伙伴"，对 hooks 功能是顺带使用。她对生成效果的"可爱度"敏感。

### 2.2 用户故事与验收标准（User Stories & Acceptance Criteria）

**US-0：首次启动引导（Onboarding）**
> 作为新用户，我想第一次打开 App 时被顺畅地引导：先得到我的宠物，再被提示把它接进我的编码工具，这样我能快速上手且不被配置吓到。

验收标准：
- 首启依次引导：**① 欢迎 → ② 生成宠物（复用照片导入面板，US-1）→ ③ 安装 hooks（US-5）→ 完成**；遵循"先给到宠物、再谈集成"。
- 第 ③ 步**只列出本机检测到的工具**（存在 `~/.claude/` 或 Codex 配置才显示），各带勾选与当前安装态；**未检测到任何工具**时显示可读提示并允许跳过。
- 整个 hooks 安装步**可"以后再说"**，不阻塞；跳过后宠物仍正常陪伴，用户可日后在设置页安装（US-5、§5.4）。
- 引导仅首启出现；完成后宠物落到桌面进入待机。

**US-1：生成我的宠物**
> 作为用户，我想上传一张宠物/人物照片，得到一个会动的桌面宠物，这样桌面就有了我专属的伙伴。

验收标准：
- 通过一个**紧凑面板**完成全流程，面板内容随状态原地变形（拖拽/选图 → 生成进度 → 结果预览+命名 → 落到桌面），无多步向导翻页；该面板首次启动与日后"换宠物"复用。
- 支持拖拽或文件选择导入 JPG/PNG/HEIC；**导入即自动开始抠图**，无需再点"生成"。
- 使用本地 Vision 框架抠出主体，生成带透明通道的精灵图，全程不联网；照片含多个主体时，MVP **自动取面积最大的主体**（多主体点选/合成排入后续版本）。
- 抠图过程中显示进度；完成后进入结果预览，用户可**为宠物命名（可选，预填占位名，可直接跳过）**，确认后宠物落到桌面默认右下角并具备待机动画（呼吸 / 偶尔眨眼或轻微晃动）。
- 抠图失败（无明显主体）时在面板内给出可读的错误提示，并允许"换一张"或"重试"。

**US-2：日常陪伴**
> 作为用户，我想让宠物平时安静待在桌面、可拖动位置、启动时跟我打个招呼，这样它有陪伴感但不碍事。

验收标准：
- 宠物为无边框、背景透明、始终置顶的浮动窗口，可鼠标拖动移动。
- 首次启动时出现在主屏右下角（贴 Dock 上方）；可拖到屏幕任意位置，松手时若靠近屏幕边缘自动吸附对齐并可沿边滑动，关闭后记住位置。
- MVP 仅支持主屏，宠物始终约束在主屏可用区域内；多屏放置排入后续版本。
- 透明区域鼠标事件穿透（不挡住下层应用），仅宠物本体响应点击/拖动。
- App 启动或每日首次唤醒时播放一次"打招呼"动画 + 气泡问候。
- 可通过菜单栏图标隐藏/显示宠物、切换宠物、退出。

**US-3：决策提醒 + 一键决策**
> 作为用户，当 Claude Code 或 Codex 需要我批准某个操作时，我想让宠物当场提醒我并直接给我"允许/拒绝"按钮，这样我不用切回终端。

验收标准：
- Agent 触发决策类 hook 时，宠物播放"提醒"动画并弹出气泡，展示操作摘要（工具名 / 命令 / 目标文件）与"允许""拒绝"按钮。
- 气泡紧贴宠物、以小尾巴指向它，并朝屏幕内侧展开、避让屏幕边缘；多个待决策请求堆叠显示并标注"还有 N 个待处理"。
- 点击"拒绝"：工具调用被真实取消（Claude Code 经 `PreToolUse` 返回 `deny`；Codex 经 `PermissionRequest` 返回 deny）。
- 点击"允许"：工具调用放行（"允许一次"；命中 `alwaysAllow` 时另有"始终允许"）。
- 用户在超时时间内未响应，或 App 未运行：hook **fail-open**，回退到工具自身的原生审批流程，绝不卡住开发者。

**US-3b：结构化提问（多选题）**
> 作为用户，当 Claude Code 用 `AskUserQuestion` 问我多选题时，我想直接在宠物气泡里点选答案，这样不用切回终端。

验收标准：
- 宠物气泡渲染题干 + 选项（含多选 / 自由文本），点选并提交后答案经 hook `updatedInput` 预填回工具，工具不再弹原生提问。
- Codex 暂不支持气泡内作答：降级为提醒 + 引导回终端处理（纯 hook 限制，见技术方案 §4.2）。
- 未作答超时：fail-open，回退原生提问。

**US-4：完成 / 状态通知**
> 作为用户，当 Agent 完成一轮任务或报错时，我想让宠物提醒我一下（无需我做决策），这样我能及时回到工作。

验收标准：
- 接收 Claude Code 的 `Stop`（完成，Markdown 摘要）/ `Notification`（状态）、Codex 的 `notify`（`agent-turn-complete`）事件。
- 宠物播放轻量提醒动画 + 气泡文案，不带按钮，数秒后自动收起。
- MVP 仅展示完成摘要，**不做"回复 Agent"**（排入 v1.1）。

**US-5：一键安装/卸载 hooks**
> 作为用户，我想一键把 VibePet 的 hooks 装进 Claude Code / Codex 配置，也能干净卸载，这样我不必手动改配置文件。

验收标准：
- 提供安装器（CLI 或 App 内按钮），自动向 `~/.claude/settings.json` 与 Codex `config.toml` 写入 hook 条目，并做幂等处理（重复安装不重复写入）。
- **写入前明确告知并确认**：点"安装"后先展示将修改的配置文件路径、将拷贝 hook 二进制到稳定路径（§1.2）、以及已自动备份原配置，用户确认后才落盘。
- 通过 **manifest 文件**记录 VibePet 写入的条目与 hook 二进制版本，据此实现幂等校验、安装态显示与精确卸载。
- 卸载时按 manifest 精确移除 VibePet 写入的条目，保留用户其它 hooks 配置；不覆盖用户已有的非 VibePet 自定义条目。
- 安装前自动备份原配置文件。
- 安装态可见：CLI `status` 与 App 设置页据 manifest 显示各工具"已安装 / 未安装 / 版本落后"。

### 2.3 非目标（Non-Goals，MVP 不做）

- ❌ **3D 宠物**：MVP 仅 2D；3D（TripoSR/Hunyuan3D + SceneKit/RealityKit）排入 v2.0，但生成接口预留。
- ❌ **照片风格化/卡通化**：MVP 仅本地抠图（真实主体剪影），不做云端 img2img 萌化；接口预留，v1.1 再做。
- ❌ **多主体点选 / 合成**：MVP 自动取最大主体；让用户在多个主体间点选、或把多主体合成一个宠物，排入后续版本。
- ❌ **Cursor 及其它工具**：MVP 仅 Claude Code + Codex；适配层抽象好，后续扩展。
- ❌ **跳回终端定位**：open-island 式"点击跳回对应终端"排入 v1.1。
- ❌ **宠物 AI 对话/人格**：不接 LLM 聊天，排入 v2.0。
- ❌ **Windows / Linux**：仅 macOS。
- ❌ **多屏放置**：MVP 宠物仅在主屏；副屏放置与跨屏位置记忆排入后续版本。
- ❌ **账号、云同步、遥测**：纯本地、无服务器、无登录。

---

## 3. AI / 系统能力需求（AI System Requirements）

> 本项目的"AI"主要体现在**本地视觉抠图**与**对外部 AI Agent 的 hook 集成**，而非自建大模型。

### 3.1 工具与依赖
| 能力 | 技术 | 说明 |
|---|---|---|
| 本地主体抠图 | Apple Vision `VNGenerateForegroundInstanceMaskRequest`（macOS 14+） | 设备端神经网络，跑在 Neural Engine，毫秒级、纯本地、不联网。 |
| 宠物渲染/动画 | SwiftUI + Core Animation（无 AI） | 程序驱动的呼吸/眨眼/拖动/打招呼动画。 |
| Claude Code 决策拦截 | `PreToolUse` hook（输出 `permissionDecision: allow/deny`） | 可阻塞工具执行并实时回传决策。 |
| Claude Code 通知 | `Notification` / `Stop` hook | 单向通知。 |
| Codex 决策拦截 | `PermissionRequest` lifecycle hook（allow/deny） | 审批前触发，可放行/拒绝。 |
| Codex 通知 | `notify` 外部程序（`agent-turn-complete`） | 目前仅任务完成事件；"需输入"类提醒以 `PermissionRequest` 覆盖。 |
| 未来：风格化 | 云端 img2img（v1.1，需用户显式开启 + API key） | 接口预留。 |
| 未来：3D | TripoSR / Hunyuan3D（v2.0） | 接口预留。 |

### 3.2 质量评估策略（Evaluation Strategy）

**抠图质量评估（离线基准）**
- 构建 20 张测试照片集（含猫/狗/人物，覆盖清晰主体、毛发边缘、低对比度、多主体等场景）。
- 人工主观打分（边缘质量 1–5 分），"≥3 分可接受"判定为通过；目标通过率 ≥ 80%（清晰主体子集 ≥ 90%）。
- 记录每张耗时，校验 P50/P95 时延目标。

**决策回路评估（端到端）**
- 脚本化触发 Claude Code `PreToolUse` 与 Codex `PermissionRequest`，断言：
  - 气泡出现延迟 ≤ 500ms；
  - 点击"拒绝"后工具调用确被取消（检查 Agent 行为/输出）；
  - 点击"允许"后工具放行；
  - App 未运行/超时场景下 hook 在 ≤ 2s fail-open 退出。

---

## 4. 技术规格（Technical Specifications）

> 完整技术设计见 [《VibePet 技术实现方案》](./VibePet-技术实现方案.md)。此处仅列高层概要。

### 4.1 架构概览
采用**方案 A**：单一 Swift Package，拆为四个 target，hook 进程与 App 通过 **Unix domain socket** 通信。

- `VibePetApp` —— SwiftUI 桌面宠物 + 菜单栏 + 设置 UI（宿主应用）。
- `VibePetCore` —— 共享库：数据模型、Bridge 传输、生成管线、持久化、工具适配协议。
- `VibePetHooks` —— 微型 CLI 二进制，被各工具的 hook 调用，转发事件并（决策类）阻塞等待回传。
- `VibePetSetup` —— 安装/卸载 CLI，幂等写入工具配置。

数据流（决策类事件）：
```
AI 工具 hook 触发 → VibePetHooks CLI（含事件 JSON, stdin）
  → Unix socket 发送 envelope → VibePetApp BridgeServer
  → PetController 弹出气泡（允许/拒绝）→ 用户点击
  → 决策经 socket 回传 CLI → CLI 按工具格式输出 JSON 到 stdout, exit 0
  → AI 工具据此放行/取消
```

### 4.2 集成点
- **Claude Code**：`~/.claude/settings.json` 注册 `PreToolUse` / `Notification` / `Stop` hooks。
- **Codex**：`config.toml` 注册 `PermissionRequest` hook 及 `notify` 程序。
- **进程间通信**：`~/Library/Application Support/VibePet/bridge.sock`（目录 0700，套接字 0600）。
- **本地文件**：宠物素材与配置存于 `~/Library/Application Support/VibePet/`。

### 4.3 安全与隐私
- **纯本地优先**：MVP 抠图全程在设备端，照片永不离开本机。
- **未来云能力显式授权**：风格化/3D 云端能力默认关闭，需用户显式开启并自带 API key。
- **IPC 最小权限**：socket 目录/文件仅当前用户可读写。
- **配置安全**：写入工具配置前自动备份，幂等、可精确卸载。
- **Fail-open 原则**：任何 VibePet 侧异常都不得阻塞用户的 AI 工具。

---

## 5. 风险与路线图（Risks & Roadmap）

### 5.1 技术风险与缓解
| 风险 | 影响 | 缓解 |
|---|---|---|
| Vision 抠图对蓬松毛发/半透明边缘有瑕疵 | 部分照片观感差 | 设定"主体清晰"的引导提示；提供手动重试/换图；v1.1 用云端风格化提升观感。 |
| Claude Code `PreToolUse` 的 `allow` 抑制原生弹窗存在已知 bug（特定版本） | "允许"路径可能仍弹原生确认 | `deny`（拒绝/阻断）路径可靠，优先保障；`allow` 作尽力而为并在文档标注；必要时回退 defer。 |
| Codex `notify` 仅 `agent-turn-complete`，覆盖"需输入"有限 | Codex 通知面偏弱 | 决策场景用 `PermissionRequest` hook 覆盖；通知面待官方扩展。 |
| 阻塞型 hook 等待导致 Agent 卡顿 | 体验/可用性 | 超时 fail-open（默认数秒）；App 未运行立即退出回退原生流程。 |
| 置顶窗口在全屏 App / 多 Space 表现异常 | 宠物被遮挡 | 设置合适的窗口层级与 collectionBehavior；在全屏场景验证。 |
| App 公证/权限（如未来跳回终端需辅助功能权限） | 分发与体验 | MVP 不依赖辅助功能；分发前做签名与公证。 |
| 参考项目 open-vibe-island 为 GPL-3.0（copyleft） | 误用其源码会传染许可证 | 仅借鉴架构思想，clean-room 独立实现，不复用源码；依据工具方公开 API（详见技术方案 §11）。 |

### 5.2 分阶段路线图
**MVP（v0.1）—— 本文档范围**
本地抠图 2D 宠物 · 浮动窗 + 待机/打招呼动画 · 菜单栏 · Claude Code + Codex 适配 · 四种气泡交互态（审批 / 结构化提问 / 完成通知 / 状态；Codex 提问降级回终端）· 安装/卸载 CLI · 可插拔生成管线（仅本地实现）。

**v1.1**
云端风格化生成器（显式开启）· 更丰富动画与情绪 · open-island 式跳回终端 · 更多事件类型 · 可选 notch UI。

**v2.0**
3D 生成器（TripoSR/Hunyuan3D）+ SceneKit/RealityKit 渲染 · 更多工具（Cursor 等）· 宠物人格 / LLM 对话。
