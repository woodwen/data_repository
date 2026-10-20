## Context

方案提出时脚本版本 2.2.0，入口为 `init-codex-project.sh`。本机 OpenSpec 1.14.1、Node.js 22.17.0；当前工作区在创建本方案前干净。已有 11 项隔离回归测试，npm/npx/OpenSpec 均由替身模拟。

本仓库此前没有 OpenSpec 根配置或 specs；使用现有 CLI 创建最小 change 目录承载本方案，不运行项目初始化脚本，也不安装 OpenSpec 项目技能。

### 已核实的上游资料（2026-10-20）

- [OpenSpec v1.14.3 发布说明](https://github.com/Fission-AI/OpenSpec/releases/tag/v1.14.3)：已发布 GitHub release，修复 linked specs、glob 和校验终端问题。其 [package.json](https://github.com/Fission-AI/OpenSpec/blob/v1.14.3/package.json) 声明 Node.js >=20.19.0。实施阶段已通过 npm 元数据查询及临时安装确认目标包。
- [Skills CLI npm 元数据](https://registry.npmjs.org/skills/latest)：本轮返回 1.7.4、Node.js >=22.20.0。[上游 README](https://github.com/vercel-labs/skills) 同样声明该 Node.js 门槛。
- [Matt Pocock README](https://github.com/mattpocock/skills)：同时提供 Codex 插件和可编辑文件安装路径，提示避免两种方式重复安装；当前 9 个技能仍列在上游。
- [Skills CLI 命令文档](https://github.com/vercel-labs/skills/blob/main/docs/commands.md)：支持按名称选择、Codex agent、项目级复制及 GitHub tree URL；`skills update` 支持名称和项目作用域。文档 main 不能替代固定版本的实际集成测试。
- [安装器源码](https://github.com/vercel-labs/skills/blob/main/src/installer.ts)：copy 模式先清理目标目录，因此升级需要保护现有内容。

实施核实：npm 的 OpenSpec 1.14.3 和 Skills CLI 1.7.4 包及 engines 已验证；可使用本机已有 Node.js 24.21.0 进行隔离测试，不更改默认 Node.js。Matt Pocock HEAD 为 `5beb35b040e3de97e54fa9e386d7e42d15c295c2`，已在临时项目用 Skills CLI 1.7.4 的固定 tree URL 成功安装全部 9 个技能。项目 skills-lock.json 记录 source、ref、skillPath、computedHash；本次项目安装未产生用户级状态文件，仍用 XDG_STATE_HOME 隔离其可能使用的用户追踪文件。

## Goals / Non-Goals

**Goals**：安装目标可追溯；初始化与升级的副作用明确；环境不兼容尽早失败；升级已有技能时保留恢复副本；旧版保护行为有回归证据。

**Non-Goals**：本机工具实际升级、自动 Node.js 升级、全量技能安装、插件迁移、用户级技能管理、自动合并技能定制、自动全局回滚、定时更新器、多套版本配置系统。

## Decisions

### 1. 固定工具版本和技能来源提交

已确认脚本中集中维护 `OPENSPEC_VERSION=1.14.3`、`SKILLS_CLI_VERSION=1.7.4` 和 `MATT_SKILLS_REF=5beb35b040e3de97e54fa9e386d7e42d15c295c2`。所有安装命令消费这些值，不再使用 `@latest`。脚本仍保持可独立复制执行，不新增必须伴随分发的配置文件或版本覆盖参数。

Matt Pocock 使用固定提交对应的 GitHub tree URL 交给固定版本 Skills CLI，按名称发现技能，避免硬编码上游的 engineering/productivity 目录。已在临时项目验证来源格式、全部 9 个技能及锁文件中的固定 ref。

备选：每次实时解析 latest 能更快跟进，但行为随时间变化且需动态处理 Node.js 要求，不推荐作为本次默认。

### 2. 默认初始化与显式升级

新增的公开参数仅为 `--upgrade` 和 `--help`；未知参数先报错，不执行安装。

| 对象状态 | 默认运行 | `--upgrade` |
| --- | --- | --- |
| OpenSpec 缺失 | 安装固定目标 | 安装固定目标 |
| OpenSpec 低于目标 | 提前停止，提示显式升级 | 安装固定目标 |
| OpenSpec 等于目标 | 复用 | 复用 |
| OpenSpec 高于目标 | 保留并报告实际版本 | 保留，不降级 |
| Matt 技能缺失 | 安装固定来源 | 安装固定来源 |
| Matt 技能已有普通目录 | 原样保留，按现有规则校验 | 备份后刷新 |
| Matt 技能路径是文件、链接或异常目录 | 保留，最终检查按现有规则报告 | 写操作前停止，要求手动处理 |

OpenSpec 版本号无法解析时停止，不能把失败输出当作“缺失”并覆盖。更高版本仅表示保留，不宣称已完成兼容性认证；后续配置/命令失败按失败阶段报告。CLI 基线提升后，日常升级通过新版本脚本的 `--upgrade` 完成，不意味着追随运行时最新上游。

### 3. 执行前检查

解析参数后先检查 Node.js >=22.20.0，以及 node/npm/npx/git 和实际使用的文件操作命令；Git 成为必需，因为技能来源是 Git 仓库。Node.js 不满足时，在 npm 安装、OpenSpec 刷新和项目文件写入前退出。

存在可用 OpenSpec 时先读取 delivery；已有项目额外读取 profile/workflows，沿用 2.2.0 的拒绝条件。若旧 CLI 无法读取这些设置，停止并显示具体错误，提示独立处理工具升级；不自动重置全局配置。新装/升级后再次检查配置，然后才刷新项目。

显式升级还须预检所有受管理技能路径和备份目的地。备份完成以前不升级全局工具、不刷新项目。全局 OpenSpec 安装成功但后续检查失败时，明确提示该全局变更已发生。

### 4. 技能备份与限定范围

默认使用 `--agent codex --copy --yes --json`，只管理现有 9 个名称。固定 Skills CLI 1.7.4 的普通输出模式可能在逐技能失败或部分请求名称不存在时返回 0；JSON 模式对此返回非零，因此用它保证失败判断准确。不用无筛选的 `skills update`，不触碰其他来源技能、用户级目录或插件配置。

`--upgrade` 在 `.init-codex-backups/<唯一运行目录>/` 保存即将替换的技能目录、已有项目 `skills-lock.json` 和简短清单（目标版本、来源提交、原路径及原先缺失项）。该路径位于 `.agents/skills` 外；以独占创建保证同秒重跑不覆盖旧备份。打印完整路径，不自动删除，不自动改 `.gitignore`。

若目标技能目录、其父技能目录、锁文件或备份父路径含不受支持的符号链接/文件类型，升级在修改前停止，避免复制或覆盖到项目外。正常默认模式仍保持原有路径保留行为。

若已有锁文件明确记录所选技能来自其他 source，则预检停止，不覆盖该同名技能；无锁文件的旧技能可在备份后刷新。技能目录内部的符号链接保持为链接；FIFO 等特殊文件会明确触发备份失败，避免复制库静默遗漏。备份失败则不执行后续修改。技能安装失败则立即非零退出，保留备份并报告可能部分完成，提供人工恢复步骤；不自动覆盖回滚用户可能新增的文件，不声称全局 npm 和项目修改具备事务性。锁文件整体备份仅作为恢复依据，恢复文档须说明其他技能条目也可能包含其中。

### 5. 可见输出与文档

输出模式、OpenSpec 安装前后版本、Skills CLI 固定版本、Matt 来源提交、保留/安装/刷新技能列表以及备份路径。成功沿用现有 readiness 规则；出现错误不输出 READY。实施时同步 README、CHANGELOG 和脚本版本，下一版本为 2.3.0。

## Risks / Trade-offs

- Node.js 门槛上调影响现有用户；README 明示，脚本不承担运行时管理。
- npm 全局安装影响同一 prefix 下其他项目；默认复用与显式升级降低意外变更，仍须明确提示。
- 固定版本需要维护者发布新基线；以可重复验证换取即时跟进速度。
- Skills CLI 可能写入用户级追踪缓存；不把这等同于安装用户级技能。测试必须隔离其实际使用的配置/缓存路径。
- 保留高于目标的 OpenSpec 有未来接口变化风险；报告实际版本，配置或能力异常时停止。
- 备份保存定制内容，不自动合并到升级结果；用户需比较并迁回必要修改。备份失败或异常链接均先停，不添加强制覆盖开关。

## Migration Plan

先验证固定依赖和来源，再增补失败测试；实现前置检查、默认模式、显式升级与备份；最后更新文档并运行隔离集成测试。默认初始化命令路径保持不变，旧用户选择升级时才使用 `bash init-codex-project.sh --upgrade`。本轮仅在隔离测试环境执行此命令。

## Validation Strategy

- 模拟 Node.js 20.19、22.17、22.19 拒绝，以及 22.20 和更高版本通过；拒绝时工具调用日志与项目快照不变。
- 覆盖 OpenSpec 缺失/旧版/目标版本/更高版本/异常版本输出，以及配置读取失败和不完整 custom 的前置停止。
- 覆盖默认保留定制、显式刷新 9 个技能、不相关技能保留、备份唯一性、备份失败、异常链接、安装中断及锁文件备份。
- 回归已有 11 项测试；执行 Bash 语法与差异检查。
- 真实安装测试仅在临时 npm prefix、临时项目和隔离的配置/缓存目录运行，使用符合要求的 Node.js；核对实际版本、全部技能及前后内容。不得为了测试升级当前用户的全局工具。若环境缺失，先保留该验证任务未完成并记录准确阻塞原因。

## Accepted Decisions

2026-10-20 用户确认全部默认值：固定版本/提交；无参数保留、--upgrade 备份后替换；继续项目级复制及现有 9 个技能。无待用户决定事项。Matt Pocock SHA 和真实依赖探测已完成，完整脚本的隔离集成验证记录见 verification.md。
