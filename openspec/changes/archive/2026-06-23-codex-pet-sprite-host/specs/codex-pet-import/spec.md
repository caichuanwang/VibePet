## ADDED Requirements

### Requirement: zip 导入（为主）

拖拽导入 SHALL 接受标准 Codex 宠物 zip 压缩包（`pet.json` + spritesheet 在包根），解压、校验后按 slug 拷入 VibePet 导入目录。

#### Scenario: 标准 zip 导入
- **WHEN** 拖入根布局为 `pet.json` + `spritesheet.webp` 的 zip
- **THEN** 校验通过并落地到导入目录 `<slug>/`

### Requirement: 文件夹导入（兼收）

拖拽导入 SHALL 同时接受拖入的宠物文件夹（如直接来自 `~/.codex/pets/<slug>/`），校验后拷入导入目录。

#### Scenario: 文件夹导入
- **WHEN** 拖入含 `pet.json` + spritesheet 的文件夹
- **THEN** 校验通过并拷入导入目录

### Requirement: 单层包裹目录容忍

导入解析 SHALL 向下定位含 `pet.json` 的层级，容忍单层包裹目录（如 macOS Finder 右键压缩产生的 `boba/pet.json`）。

#### Scenario: Finder 压缩的 zip
- **WHEN** 拖入的 zip 解压后为 `boba/pet.json` + `boba/spritesheet.webp`
- **THEN** 解析定位到 `boba/` 层并成功导入，不因「根不是 pet.json」而失败

### Requirement: 非法导入拒绝

当拖入的包/文件夹缺 `pet.json` 或 spritesheet、或网格尺寸不符时，导入 SHALL 拒绝并给出可读原因，不污染导入目录。

#### Scenario: 缺文件拒绝
- **WHEN** 拖入只含 `pet.json`、无 spritesheet 的 zip
- **THEN** 拒绝导入并提示可读原因，导入目录不产生半成品

#### Scenario: 网格不符拒绝
- **WHEN** 拖入的 spritesheet 尺寸不是 1536×1872
- **THEN** 拒绝导入并提示可读原因
