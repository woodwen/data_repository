## Why

初始化脚本 2.2.0 每次执行都会全局安装 OpenSpec `@latest`，Skills CLI 也使用 `@latest`，但已有 Matt Pocock 技能始终跳过。两类依赖的升级行为不一致，无法从脚本版本确定工具目标，也没有保留定制内容的批量升级入口。

2026-10-20 核对发现 Skills CLI 1.7.4 已要求 Node.js >=22.20.0，而脚本仍只检查 >=20.19.0。需要先校验完整环境，再执行安装，避免执行到中途才发现工具不兼容。

## What Changes

- 将 OpenSpec、Skills CLI 和 Matt Pocock 来源集中为脚本内的固定版本/提交常量；基线为 OpenSpec 1.14.3、Skills CLI 1.7.4，Matt Pocock 提交为 `5beb35b040e3de97e54fa9e386d7e42d15c295c2`。
- **BREAKING**：将 Node.js 最低版本提高到 22.20.0；不自动安装或切换 Node.js。
- 默认模式补齐缺失项、复用符合基线的 OpenSpec、保留已有技能；旧版 OpenSpec 提前提示使用显式升级，不再每次安装 `@latest`。
- 增加 `--upgrade`，将旧版 OpenSpec 升至固定目标，并备份后刷新脚本管理的 9 个 Matt Pocock 项目技能；保留更高版本的 OpenSpec，不自动降级。
- 继续采用 `.agents/skills` 项目级复制安装，保持现有技能清单；不迁移到插件，不更新其他来源的技能或用户级技能。
- 升级前完成配置检查、目标检查和技能备份，输出版本、路径及失败阶段；失败时停止并保留恢复依据，不宣称全局升级已回滚。
- 实施时更新 README、CHANGELOG 和回归测试，保留 2.2.0 的配置、文档及就绪检查。

## Capabilities

### New Capabilities

- `initializer-dependency-management`：初始化器的依赖基线、默认安装、显式升级、技能保护与失败报告。

### Modified Capabilities

无。仓库此前没有已发布的 OpenSpec specs。

## Impact

- 实施文件：`init-codex-project.sh`、`tests/test_init_codex_project.py`、`README.md`、`CHANGELOG.md`。
- 使用者：Node.js 20.x 和低于 22.20.0 的 22.x 环境将不再通过前置检查；已有旧版 OpenSpec 需显式升级。
- 运行副作用：缺失安装或显式升级仍可能修改当前 npm prefix 下的全局 OpenSpec；技能仅作用于当前项目，升级备份留在项目的非技能发现目录。
- 当前已进入实施阶段；安装测试仅在隔离环境运行，不升级用户全局工具，不提交或推送。

## Accepted Defaults

2026-10-20 用户已确认全部默认值并授权实施：固定依赖基线；默认保留、`--upgrade` 显式升级；继续项目级复制安装与现有 9 个技能。具体理由、备选方案和调查边界见 `design.md`。
