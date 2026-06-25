## Requirements

### Requirement: 多根聚合读取

`PetAssetStore` SHALL 聚合两个根目录——共享 `~/.codex/pets/`（只读、原地引用）与 VibePet 导入目录 `~/Library/Application Support/VibePet/pets/`——解析各 `pet.json`、校验后按 **slug** 去重（导入目录优先），返回 `[PetAsset]`。共享目录的宠物 MUST 原地引用、不拷贝（Codex 新装即可选）。

#### Scenario: slug 去重导入优先
- **WHEN** 两根目录存在同一 slug 的宠物
- **THEN** 返回导入目录版本，共享版本被去重

#### Scenario: 共享宠物原地引用
- **WHEN** 用户在 Codex 新装一个宠物到 `~/.codex/pets/`
- **THEN** VibePet 下次 `list()` 即出现该宠物，无需拷贝

### Requirement: pet.json 解析与校验

SHALL 解析 Codex `pet.json`（`id` / `displayName` / `description` / `spritesheetPath`），校验 spritesheet 存在且整图尺寸符合 8×9×192×208（1536×1872）。校验失败的宠物 SHALL 跳过并记录可读原因，不影响其它宠物。`slug` 取文件夹名。

#### Scenario: 合法宠物解析
- **WHEN** 读取含合法 `pet.json` + 1536×1872 spritesheet 的文件夹
- **THEN** 产出对应 `PetAsset`，`slug` = 文件夹名

#### Scenario: 网格不符跳过
- **WHEN** 某宠物 spritesheet 尺寸不是 1536×1872
- **THEN** 跳过该宠物并记录可读原因，其余宠物正常返回

### Requirement: 共享目录缺失容错

当 `~/.codex/pets/` 不存在时（用户没装 Codex），`list()` SHALL 正常返回（仅导入目录结果或空），不报错。

#### Scenario: 没装 Codex
- **WHEN** `~/.codex/pets/` 不存在且导入目录为空
- **THEN** 返回空列表，不抛错

### Requirement: 旧 UUID 格式忽略

当导入目录存在旧版 `~/Library/Application Support/VibePet/pets/<UUID>/`（含 `meta.json`/`sprite.png`，非 Codex 格式）时，聚合读取器 SHALL 忽略它——不崩、不迁移、不提示。

#### Scenario: 旧用户残留
- **WHEN** 导入目录存在旧 UUID 宠物文件夹
- **THEN** 聚合结果不含它，且不报错

### Requirement: 空状态引导

当无任何可用宠物时，UI SHALL 显示平台中立的可读引导（用任意方式把宠物装进 `~/.codex/pets/`，或直接拖入一个宠物），而非空白或崩溃，且不阻塞（可「以后再说」）。

#### Scenario: 首启无宠物
- **WHEN** 聚合返回空列表
- **THEN** 宠物区显示空状态引导而非空白，用户可稍后继续
