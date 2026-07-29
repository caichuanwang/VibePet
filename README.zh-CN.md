# VibePet

[English](README.md) | **简体中文** | [繁體中文](README.zh-TW.md)

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

**一个面向 Claude Code 和 Codex 的开源、本地优先 macOS 桌面宠物。**

VibePet 让 AI 编程会话保持可见，而不需要你一直盯着终端。Agent 工作时，宠物会切换动画；需要审批或回答问题时，它会在桌面气泡中提醒你；它还能聚合多个会话，并跳回需要你处理的终端。

![VibePet 手绘概念图：桌面宠物在本地编程 Agent 旁显示审批操作](imgs/vibepet-hero.png)

*概念图，并非产品截图。*

一切都在你的 Mac 上运行。VibePet 不需要账号、云服务、遥测或远程生成服务。

> [!IMPORTANT]
> VibePet 仍处于早期阶段。GitHub 二进制版本仅使用 ad-hoc 签名，没有 Apple Developer ID 签名，也未经过 Apple 公证，因此首次启动时 Gatekeeper 会发出警告。工具的 Hook 格式和用户可见行为仍可能随版本变化。

## 为什么选择 VibePet？

编程 Agent 最适合在后台运行，但当终端被其他窗口遮住后，权限请求和问题很容易被错过。VibePet 将这些隐藏的等待状态转化为一个小巧、常驻的桌面界面：

- **了解 Agent 正在做什么**：宠物动画会反映运行中、等待响应、已完成、失败和空闲等状态。
- **直接在桌面响应**：在气泡中允许、拒绝或回答受支持的请求。
- **跟踪多个会话**：菜单栏计数和会话面板会聚合不同终端中的 Claude Code 与 Codex 活动。
- **跳回会话来源**：如果已捕获上下文，可返回发起请求的终端或编辑器。
- **使用 Codex 格式宠物**：发现 `${CODEX_HOME:-~/.codex}/pets/` 中的宠物，或导入本地文件夹、ZIP 包。

## 支持的集成

| 集成 | 当前支持 | 说明 |
| --- | --- | --- |
| Claude Code | 审批、结构化问题、通知和会话生命周期 | 在桌面回答 `AskUserQuestion` 需要 Claude Code 2.1.85 或更高版本。已知的 Claude Code 回归问题可能仍会显示原生提示；VibePet 会回退到原生流程，而不会阻塞 Agent。 |
| Codex | 审批、回合完成通知和部分会话生命周期 | Codex 可能要求通过 `/hooks` 信任已安装的 Hook。无法通过 Hook API 回答的问题会回退到终端。 |

终端跳转专门支持 **Apple Terminal、iTerm2、Ghostty、cmux 和 VS Code**。无法精确定位会话时，会安全地回退到对应应用和工作目录。

VibePet 目前只面向 Claude Code 和 Codex。Cursor、Gemini、Windows 和 Linux 不在当前范围内。

## 环境要求

- macOS 14 或更高版本
- GitHub 提供的通用架构版本；从源码构建时需要 Xcode 或支持 Swift 6 的 Apple Swift 工具链
- 用于 Agent 集成的 Claude Code 和/或 Codex
- 一个 Codex 格式的宠物包（`pet.json` 及其 spritesheet），可以来自共享 Codex 宠物目录，也可以从本地导入

发布包不包含内置宠物；请在首次启动时选择已有的 Codex 格式宠物或导入一个宠物包。

## 下载与安装

1. 从 [GitHub Releases 最新版本](https://github.com/caichuanwang/VibePet/releases/latest)下载 `VibePet-v<版本号>-macos-universal.zip` 和 `SHA256SUMS`。
2. 在绕过 Gatekeeper 前验证压缩包校验值：

   ```sh
   cd ~/Downloads
   shasum -a 256 VibePet-v*-macos-universal.zip
   cat SHA256SUMS
   ```

   ZIP 对应的 SHA-256 必须与 `SHA256SUMS` 中的记录完全一致。
3. 解压后将 `VibePet.app` 拖入 `/Applications`（应用程序）目录。
4. 打开 VibePet。由于发布包没有经过 Apple 公证，如果 macOS 阻止启动，请使用下面任一方法。

### 首次打开若提示“来自未知开发者/已被隔离”如何解决

仅对从本仓库官方 Releases 页面下载且 SHA-256 校验一致的 VibePet 使用以下方法。

**方法一：系统设置（推荐）**

1. 先尝试打开一次 VibePet，然后关闭警告。
2. 打开“系统设置”→“隐私与安全性”。
3. 找到 VibePet 相关提示，点击“仍要打开”，再确认“打开”。

**方法二：终端命令**

仅移除已安装 VibePet 的隔离属性，然后启动应用：

```sh
xattr -dr com.apple.quarantine /Applications/VibePet.app
open /Applications/VibePet.app
```

如果第一条命令提示权限不足，再仅为该命令添加一次 `sudo`。不要对来源不明的应用执行解除隔离命令。

### 为首次运行准备宠物

如果 Codex 已在 `${CODEX_HOME:-~/.codex}/pets/` 中安装宠物，VibePet 会自动发现它们。你也可以使用 OpenAI 精选的 [`hatch-pet` skill](https://github.com/openai/skills/tree/main/skills/.curated/hatch-pet) 创建兼容宠物，或者尝试第三方 [Awesome Codex Pets](https://github.com/gennadi-kuzmin/awesome-codex-pets) 合集中的宠物。

例如：

```sh
git clone --depth 1 https://github.com/gennadi-kuzmin/awesome-codex-pets.git /tmp/awesome-codex-pets
mkdir -p "${CODEX_HOME:-$HOME/.codex}/pets"
cp -R /tmp/awesome-codex-pets/pets/terminal-ghost "${CODEX_HOME:-$HOME/.codex}/pets/"
```

社区宠物是独立项目；安装前请检查其源码和许可证。

## 从源码构建并运行

克隆仓库并构建所有目标：

```sh
git clone https://github.com/caichuanwang/VibePet.git
cd VibePet
swift build
```

启动应用：

```sh
swift run VibePetApp
```

首次启动时，引导流程会帮助你：

1. 选择 `${CODEX_HOME:-~/.codex}/pets/` 中已有的宠物；
2. 导入 Codex 格式的宠物文件夹或 ZIP 文件；
3. 为检测到的 Claude Code 和 Codex 安装 VibePet Hook。

导入的宠物会复制到：

```text
~/Library/Application Support/VibePet/pets/
```

完成引导后，在使用 Claude Code 或 Codex 时请保持 VibePet 运行。打开菜单栏项目即可查看活动数和待处理数，也可以管理宠物显示、切换、导入和设置。点击桌面宠物可打开会话面板。

### 通过 CLI 安装 Hook

应用可以通过首次启动引导和“设置”管理 Hook。对于源码构建，Setup CLI 提供相同的核心操作：

```sh
swift run VibePetSetup install all
swift run VibePetSetup status
swift run VibePetSetup doctor
```

需要时也可以只安装一个集成：

```sh
swift run VibePetSetup install claude
swift run VibePetSetup install codex
```

执行 `install all` 时，只有已经存在主要配置文件的集成才会自动修改。如果希望无论配置文件是否存在都安装某个集成，请显式执行 `install claude` 或 `install codex`。

安装器会将 `VibePetHooks` 复制到以下稳定位置，而不会让工具配置指向 `.build/`：

```text
~/Library/Application Support/VibePet/bin/VibePetHooks
```

安装器只管理 VibePet 自己的 Claude Code 和 Codex 配置项，会将安装状态记录到清单中，并保留无关的用户 Hook。安装 Codex 集成后，如果 Codex 要求确认信任，请在 Codex 中打开 `/hooks`。

### 诊断或卸载 Hook

在不修改配置的情况下检查安装是否发生漂移：

```sh
swift run VibePetSetup doctor
```

移除 VibePet 管理的 Hook，同时保留无关配置：

```sh
swift run VibePetSetup uninstall all
```

也可以使用 `uninstall claude` 或 `uninstall codex` 单独卸载某个集成。

## 宠物包格式

VibePet 使用 Codex spritesheet 宠物格式：

```text
my-pet/
├── pet.json
└── spritesheet.webp
```

图集尺寸必须严格为 **1536 × 1872 像素**：8 列 × 9 行，每帧占据一个 **192 × 208 像素**的单元格。清单引用的 spritesheet 支持透明 PNG 和 WebP 格式。

最小的 `pet.json` 如下：

```json
{
  "id": "my-pet",
  "displayName": "My Pet",
  "description": "A tiny coding companion.",
  "spritesheetPath": "spritesheet.webp"
}
```

`id`、`displayName` 和 `spritesheetPath` 为必填字段，`description` 可选。spritesheet 路径必须位于宠物文件夹内。VibePet 当前根据文件夹名生成运行时 slug；对于根目录直接包含宠物文件的 ZIP 包，则根据 ZIP 文件名生成。因此，替换或覆盖宠物时请谨慎选择名称。

宠物来源按以下方式合并：

- **共享 Codex 宠物库：**直接读取 `${CODEX_HOME:-~/.codex}/pets/`，不会复制文件。
- **VibePet 导入：**通过首次启动引导或菜单选择的文件夹、ZIP 包会先经过验证，再复制到 VibePet Application Support 目录。
- 如果导入宠物与共享宠物使用相同的 slug，导入版本优先。

VibePet 不会下载宠物，也不提供应用内在线宠物画廊。

## 隐私与安全

VibePet 围绕两条不可妥协的边界设计。

### 本地优先

Bridge 通信使用本地 Unix domain socket。宠物发现、Hook 处理、会话状态、配置和渲染都保留在 Mac 上。本项目不会添加：

- 账号或云同步；
- 遥测或分析数据上传；
- 远程宠物生成；
- Prompt 或会话内容上传；
- 在线宠物市场。

### 失败时回退

Agent 集成不能依赖 VibePet 始终正常运行。如果应用未运行、socket 无法连接、输入格式错误或决策超时，Hook 会交回编程工具的原生流程，而不会让 Agent 挂起。

任何破坏原生回退流程的回归都应被视为高优先级问题。

## 本地数据与重置

VibePet 将自己管理的状态存放在：

```text
~/Library/Application Support/VibePet/
```

其中包括应用配置、导入的宠物、Bridge socket、稳定的 Hook 辅助程序，以及安装清单和备份。`${CODEX_HOME:-~/.codex}/pets/` 下的共享 Codex 宠物库属于外部数据，不是 VibePet 应用状态的一部分。

要让 VibePet 恢复到首次启动状态：

1. 退出 VibePet。
2. 运行 `swift run VibePetSetup uninstall all`，安全移除由 VibePet 管理的 Hook 配置。
3. 确认卸载成功后，删除 `~/Library/Application Support/VibePet/`。
4. 再次启动 VibePet。

如果安装清单丢失或损坏，请**不要**轻信 CLI 输出的 `uninstalled`，也不要先删除 Application Support 目录，因为 CLI 可能没有找到任何受管理记录。请只从 `~/.claude/settings.json` 和 `${CODEX_HOME:-~/.codex}/hooks.json` 中手动移除引用 `~/Library/Application Support/VibePet/bin/VibePetHooks` 的 Hook；由 VibePet 管理的 Codex Hook 组也可能包含 `statusMessage: "Managed by VibePet"`。只有在没有其他 Codex Hook 时，才移除 VibePet 管理的 Codex 功能标志。

不要删除整个 `~/.claude/` 或 `~/.codex/`，这些目录中可能包含无关的用户配置和宠物。

## 架构

![VibePet 手绘架构图：两个本地编程 Agent 通过 Hook 和 Unix socket 流向 VibePet](imgs/vibepet-architecture.png)

Swift 软件包分为四个产品：

```text
VibePetCore/    与 UI 无关的模型、适配器、Bridge、安装器、持久化和宠物逻辑
VibePetApp/     SwiftUI/AppKit 桌面应用、宠物窗口、气泡、会话面板、设置和 Bridge Host
VibePetHooks/   Claude Code 和 Codex 使用的小型失败回退 Hook CLI
VibePetSetup/   安装、卸载、状态和诊断 CLI
Tests/          Core、App、Setup 和端到端 XCTest 测试
docs/           产品需求、当前设计规范和历史设计归档
```

完整的产品与技术决策说明请参阅 [PRD](docs/VibePet-PRD.md)。

## 开发

构建软件包：

```sh
swift build
```

运行完整测试套件：

```sh
swift test
```

确认软件包产品和构建目标归属：

```sh
swift package describe --type json
```

安装器和配置写入逻辑必须使用临时文件进行单元测试。自动化开发流程中不要执行真实安装冒烟测试，因为即使覆盖 `$HOME`，工具配置路径仍会解析到真实的 `~/.claude` 和 `~/.codex` 位置。

## 参与贡献

欢迎提交贡献、Bug 报告和范围明确的功能提案。

- 提交报告前，请阅读 [Issue 指南](.github/ISSUE_GUIDE.md)。
- 使用 [Issue 选择器](https://github.com/caichuanwang/VibePet/issues/new/choose)提交 Bug 或功能请求。
- 对于较大的改动，请阅读 [`docs/superpowers/specs/`](docs/superpowers/specs/) 中的相关文档，并先讨论范围。
- 保持改动精简，维护本地优先和失败回退边界，并在行为发生变化时添加针对性的 XCTest 覆盖。
- 通过 Pull Request 提交改动；`master` 分支受到保护，不能直接推送。

对于参与较大行为改动的贡献者，[PRD](docs/VibePet-PRD.md) 和当前的[设计规范](docs/superpowers/specs/)可作为可选技术背景。`AGENTS.md` 包含维护者和编程 Agent 的工作流约束，首次贡献无需阅读。

### 安全问题报告

不要在公开 Issue 中发布漏洞细节、凭据、私有 Prompt 或会话内容。仓库目前没有专门的私密漏洞报告渠道。如果无法找到维护者的私密联系方式，请只创建一个不包含漏洞细节的最小 Issue，询问应该如何安全报告。

## 项目范围

VibePet 有意保持专注：

- 仅支持 macOS 14+；
- 仅支持 Claude Code 和 Codex；
- 使用本地宠物包，不提供在线画廊；
- 使用 2D spritesheet 宠物，不使用 3D 或 LLM 驱动的角色；
- 以源码构建和项目发布版本为主，不将 Mac App Store 作为已确定的发布渠道。

这些边界可以通过明确的产品讨论发生变化，但不应在实现过程中被无意削弱。

## 致谢

VibePet 的灵感来自 Octane0411 及其贡献者开发的 [open-vibe-island](https://github.com/Octane0411/open-vibe-island)。它的模块边界、标准化 Hook/会话模型、Unix socket 桥接、安装器模式和终端跳转方案影响了 VibePet 的架构。VibePet 将这些思路调整为一个本地桌面宠物，专注于 Claude Code、Codex 和 Codex 宠物生态。

## 许可证

VibePet 是依据 [GNU General Public License v3.0](LICENSE) 许可的自由开源软件。
