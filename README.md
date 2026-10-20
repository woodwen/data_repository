# Codex 项目初始化脚本

为项目安装 OpenSpec 和选定的 Matt Pocock Skills，并生成开发规则、项目说明及工程文档模板。脚本输出工具与文档检查结果，项目的真实技术栈、命令和架构需要在初始化后补充。

## 版本

| 文件 | 版本 | 用途 |
| --- | --- | --- |
| [init-codex-project.sh](init-codex-project.sh) | 2.3.0 | 固定依赖基线、默认保留及显式升级备份 |
| [CHANGELOG.md](CHANGELOG.md) | — | 脚本更新记录、兼容性与验证范围 |

以下说明对应 **2.3.0**。原 `init-codex-project-v2.1.0.sh` 已合并到统一入口，调用旧路径的命令需更新。

## 环境要求

- Bash，以及常用的 `mkdir`、`cat`、`grep` 等命令。
- `node`、`npm`、`npx`、`git` 可从 `PATH` 调用；Node.js 必须 **>=22.20.0**（Skills CLI 的要求）。脚本不会自动升级或切换 Node.js。
- 可访问 npm 和 Skills 来源仓库的网络环境，以及 npm 全局安装目录的写权限。
- Git 必需，用于获取技能来源；当前目录可以尚未初始化为 Git 仓库。

固定安装基线集中在脚本开头，脚本仍可独立复制执行：

| 依赖 | 目标 |
| --- | --- |
| OpenSpec | `1.14.3` |
| Skills CLI | `1.7.4` |
| Matt Pocock skills | `5beb35b040e3de97e54fa9e386d7e42d15c295c2` |

安装不使用 `@latest` 或浮动 main。已有 OpenSpec 高于目标时保留并报告实际版本，不代表更高版本已经过本脚本兼容性认证。OpenSpec 安装后，其命令必须在 `PATH` 中可用；npm prefix 与 PATH 不一致会报错。

## 快速开始

进入**目标项目根目录**后运行脚本，将示例路径替换为实际路径：

```bash
cd /path/to/your-project && bash /path/to/data_repository/init-codex-project.sh
```

也可以先把脚本复制到目标项目根目录，再执行：

```bash
bash ./init-codex-project.sh
```

初始化目标是运行命令时的当前目录。脚本没有目标目录参数，不会自动切换到脚本所在目录；禁止直接在 `/` 或用户主目录运行。

```bash
bash ./init-codex-project.sh --help
bash ./init-codex-project.sh --upgrade
```

无参数运行保留已有技能。`--upgrade` 表示备份后刷新脚本管理的 9 个技能，并将低于基线的 OpenSpec 升级到固定目标；不是追随上游 latest。帮助无需安装依赖，未知参数会在写入前报错。

| 状态 | 默认运行 | `--upgrade` |
| --- | --- | --- |
| OpenSpec 缺失 | 安装固定目标 | 安装固定目标 |
| OpenSpec 低于目标 | 停止并提示显式升级 | 安装固定目标 |
| OpenSpec 等于或高于目标 | 复用，不降级 | 复用，不降级 |
| Matt 技能缺失 | 安装固定来源 | 安装固定来源 |
| Matt 技能已有普通目录 | 原样保留 | 备份后刷新 |
| Matt 技能路径异常或为链接 | 保留，按最终检查结果报告 | 写入前停止，手动处理 |

## 升级已有项目

已有项目使用 `--upgrade`，升级目标见上方固定安装基线。按以下顺序操作，每一步检查通过后再继续。

### 1. 检查环境和已有改动

进入需要升级的项目，将示例路径替换为实际路径：

```bash
cd /path/to/your-project
node --version
openspec --version
git status --short
```

Node.js 必须 >=22.20.0；版本不足时，先用自己的 Node.js 版本管理工具切换，再重新检查。切换后也应重新确认 `openspec` 是否可用，因为不同 Node.js 环境可能使用不同的 npm 全局安装目录；OpenSpec 缺失时脚本会安装固定版本。

先保存已有改动，特别是定制过的技能和 OpenSpec 生成文件，以便核对升级差异。脚本会备份受管理的 Matt 技能和 `skills-lock.json`，但不会备份 OpenSpec 生成文件或全局 npm 安装；详见[升级备份与恢复](#升级备份与恢复)。

### 2. 执行升级

保持在目标项目根目录，调用本仓库脚本：

```bash
bash /path/to/data_repository/init-codex-project.sh --upgrade
```

脚本以**当前工作目录**为目标，不以脚本所在目录为目标。升级多个项目时，需要分别进入各项目执行；它们共用的全局 OpenSpec CLI 达到基线后会被复用，各项目的技能仍需分别刷新。

升级模式会备份后刷新 `.agents/skills/` 中指定的 9 个 Matt 技能，并刷新项目 OpenSpec 生成文件。已有项目文档会保留，缺失的文档模板和基础文件会补建，因此运行后也需要检查新增文件。

### 3. 验证升级结果

脚本成功退出后执行：

```bash
openspec --version
openspec validate --all --strict
git diff --stat
git diff --check
git status --short
```

核对脚本输出中的实际版本、技能刷新列表及备份路径；查看 `git diff` 中的具体变化，并单独检查 `git status --short` 列出的未跟踪文件，`git diff --check` 不覆盖这些文件。若输出 `INITIALIZED, NOT READY FOR DEVELOPMENT`，按[初始化后的检查](#初始化后的检查)补全文档。安装失败时先按输出的失败阶段和备份路径排查，脚本不会自动回滚、提交或推送。

### 旧目录与更新范围

如果原项目的技能位于 `.codex/skills/`，脚本不会迁移、删除或刷新其中的旧副本。升级前后比较它与 `.agents/skills/` 的同名技能，先保留需要的定制内容，再决定如何处理重复副本；只有旧目录中的 OpenSpec 技能时，参照[旧项目缺少共享目录中的 OpenSpec 技能](#旧项目缺少共享目录中的-openspec-技能)及脚本提示补齐共享目录。

用户级技能和插件不在脚本的更新范围内。`--upgrade` 使用脚本固定的版本和来源提交；如果希望跟进更高版本，先更新并验证脚本开头的 `OPENSPEC_VERSION`、`SKILLS_CLI_VERSION`、`MATT_SKILLS_REF` 及所选技能名称，再对已有项目执行升级。不要把重复运行 `--upgrade` 理解为自动获取上游最新版。

## 执行内容

1. 检查环境及现有 OpenSpec 版本；无法解析版本或默认模式遇到旧版本时停止。
2. 已有 CLI 先检查全局 `delivery`，允许 `skills` 或 `both`；已有项目同时检查 profile/workflows。升级模式先验证路径、来源并完成备份，再安装必要的全局 OpenSpec；安装后重新检查配置。
3. 已有 `openspec/config.yaml` 时，先检查全局 profile，再执行 `openspec update . --force`；允许 `core`，或包含 `propose`、`apply`、`archive` 的 `custom`。新项目使用 `agents` 目标、`core` profile 和简体中文指引初始化。
4. 为 Codex 安装以下项目技能，默认保留已有路径，升级模式备份后刷新：`setup-matt-pocock-skills`、`grill-with-docs`、`grilling`、`domain-modeling`、`codebase-design`、`tdd`、`diagnosing-bugs`、`code-review`、`writing-for-agents`。
5. 创建缺失的文档和基础文件，检查必需技能、文档及占位标记。

主要产物：

```text
目标项目/
├── .agents/skills/                 # OpenSpec 和 Matt Pocock 技能
├── .github/PULL_REQUEST_TEMPLATE.md
├── .editorconfig
├── openspec/                       # 新项目的配置、specs 和 changes
├── docs/
│   ├── adr/README.md
│   ├── PROJECT.md                  # 占位文档
│   └── ARCHITECTURE.md             # 占位文档
├── AGENTS.md                       # 占位文档
├── README.md                       # 占位文档
└── CHANGELOG.md                    # 占位文档
```

已有文档和基础文件会保留；默认模式保留 Matt Pocock 技能，升级模式在备份后刷新。两个模式都会刷新项目的 OpenSpec 生成文件。脚本不会自动提交或推送 Git，也不会自动归档 OpenSpec change。

`GLOSSARY.md` / `GLOSSARY-MAP.md` 由后续领域建模按需创建。初始化后运行 `$setup-matt-pocock-skills`，完成技能的项目配置。

## 初始化后的检查

根据项目实际情况补全五份占位文档，并执行：

```bash
grep -n "PLACEHOLDER:REPLACE_ME" AGENTS.md README.md CHANGELOG.md docs/PROJECT.md docs/ARCHITECTURE.md
```

输出匹配行表示仍有占位标记；无输出且退出码为 `1` 表示没有匹配；退出码为 `2` 表示检查出错。删除标记前应先完成对应内容。

| 最终状态 | 退出码 | 含义 |
| --- | --- | --- |
| `INITIALIZED, NOT READY FOR DEVELOPMENT` | 0 | 初始化及检查完成，仍有占位文档待填写 |
| `READY FOR DEVELOPMENT` | 0 | 必需工具和文档检查通过，五份文档没有占位标记 |
| `INITIALIZATION INCOMPLETE` | 非零 | 最终检查发现工具或文档异常，需要修复后重跑 |

环境、安装或配置检查失败时，脚本也会提前以非零退出码结束，可能尚未输出最终状态。`READY FOR DEVELOPMENT` 只代表上述检查通过，不代表项目测试、Lint 或构建已通过。

## 常见情况

### OpenSpec 的 delivery 为 commands

脚本会在项目初始化或刷新前停止。如果希望改为同时交付技能和命令，可执行：

```bash
openspec config set delivery both
```

这是**全局设置**，会影响其他项目的后续 OpenSpec 操作。脚本只读取该设置，不自动修改它。已有 CLI 在安装前检查，安装后再复查；旧 CLI 无法读取配置时停止，需先单独处理。安装后的检查失败不会回滚已发生的全局安装。

### 旧项目缺少共享目录中的 OpenSpec 技能

查看脚本输出的缺失路径及修复提示。脚本会保留 `.codex/skills` 中的旧文件，不自动迁移或删除副本。已有文档里的 `CONTEXT.md` 指引也不会自动替换。

### 重复运行

可以补齐缺失文档及 Matt Pocock 技能，并重新执行检查。已有技能路径即使不完整或为悬空链接也会保留；缺少 `SKILL.md` 时最终检查会报错，需要手动处理。

需要刷新时使用 `--upgrade`。该模式只处理上述 9 个名称；锁文件明确指向其他来源的同名技能会触发停止，不自动接管。没有锁文件的旧技能可以在备份后升级。插件和用户级技能不在更新范围内；本脚本也不执行无筛选的 `skills update`。

### 升级备份与恢复

`--upgrade` 在任何全局安装、项目刷新和技能替换前创建 `.init-codex-backups/run-<唯一值>/`，保存已有受管理技能、原 `skills-lock.json` 和 `manifest.json`。清单包含目标版本、来源提交、原路径及原先缺失项。备份不位于技能发现目录，多次运行不会覆盖旧备份；脚本不自动删除备份或修改 `.gitignore`。

升级前遇到技能目录或父路径、锁文件、备份父路径的异常文件类型或符号链接会停止。锁文件损坏或格式不支持时也先停止。技能目录内部的链接按链接备份，不读取其指向的外部内容；FIFO 等不支持的特殊文件会导致备份失败，不会被静默遗漏。

失败输出包含阶段、退出码及备份路径。仅当提示备份完成且清单存在时，按以下步骤人工恢复：

1. 比较清单与当前项目；先另存安装中断后产生的新内容。
2. 将需要恢复的当前技能目录移到别处，再将备份中对应的 `.agents/skills/<名称>` 完整复制回原路径，避免合并残留文件。清单标为原先缺失的技能不在备份中，是否移除由你确认。
3. 单独比较 `skills-lock.json`。只有确认没有其他需保留的新条目时才整体恢复；否则只恢复对应技能条目。原先没有锁文件时，不要盲目删除包含其他技能的新锁文件。
4. 完成恢复后核对文件差异，再运行默认检查。备份本身保留到确认恢复完成。

备份失败时不执行后续安装；安装中断时可能已部分更新，脚本不自动回滚。备份范围是 Matt 技能和项目锁文件，不包括全局 npm 安装或 OpenSpec 生成文件；失败信息会说明全局 OpenSpec 安装是否已尝试/完成。

### OpenSpec 自定义 profile 缺少必需流程

已有项目在刷新前会检查全局 profile。若 `custom` 缺少 `propose`、`apply` 或 `archive`，脚本会停止，避免刷新时先删除这些必需技能再报告失败。通过 `openspec config` 补齐 workflows 或选择 `core` 后重跑；这属于全局设置，会影响其他项目。脚本不会自动修改这些设置，检查失败也不会回滚此前的全局安装。

## 验证范围

运行语法检查和回归测试（需 Bash、Node.js 和 Python 3）：

```bash
bash -n init-codex-project.sh
python3 -B -m unittest discover -s tests -v
```

回归测试在临时目录运行，使用 npm、npx、OpenSpec 替身及模拟 Node.js 版本，不安装工具。真实联网测试限定在临时 npm prefix、项目和 XDG 配置/缓存/状态目录，不修改用户原有全局工具。具体版本与验证结果见 [CHANGELOG.md](CHANGELOG.md)。
