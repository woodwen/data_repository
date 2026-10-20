# Codex 项目初始化脚本

为项目安装 OpenSpec 和选定的 Matt Pocock Skills，并生成开发规则、项目说明及工程文档模板。脚本输出工具与文档检查结果，项目的真实技术栈、命令和架构需要在初始化后补充。

## 版本

| 文件 | 版本 | 用途 |
| --- | --- | --- |
| [init-codex-project.sh](init-codex-project.sh) | 2.2.0 | 统一入口，包含 2.1.0 修复及重复运行保护 |
| [CHANGELOG.md](CHANGELOG.md) | — | 脚本更新记录、兼容性与验证范围 |

以下说明对应 **2.2.0**。原 `init-codex-project-v2.1.0.sh` 已合并到统一入口，调用旧路径的命令需更新。

## 环境要求

- Bash，以及常用的 `mkdir`、`cat`、`grep` 等命令。
- `node`、`npm`、`npx` 可从 `PATH` 调用；脚本检查 Node.js 版本不低于 20.19.0。
- 可访问 npm 和 Skills 来源仓库的网络环境，以及 npm 全局安装目录的写权限。
- Git 可选；未安装 Git 或当前目录尚未初始化 Git 时，脚本只提示警告。

脚本每次都会安装或更新 `@fission-ai/openspec@latest`，并通过 `skills@latest` 安装缺失的项目技能，因此实际依赖版本会随运行时间变化。OpenSpec 安装后，其命令也必须在 `PATH` 中可用。

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

## 执行内容

1. 检查环境，安装或更新全局 OpenSpec。
2. 检查 OpenSpec 的全局 `delivery` 设置，允许 `skills` 或 `both`。
3. 已有 `openspec/config.yaml` 时，先检查全局 profile，再执行 `openspec update . --force`；允许 `core`，或包含 `propose`、`apply`、`archive` 的 `custom`。新项目使用 `agents` 目标、`core` profile 和简体中文指引初始化。
4. 为 Codex 补齐以下项目技能，使用复制模式并保留已有路径：`setup-matt-pocock-skills`、`grill-with-docs`、`grilling`、`domain-modeling`、`codebase-design`、`tdd`、`diagnosing-bugs`、`code-review`、`writing-for-agents`。
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

已有文档、基础文件及 Matt Pocock 技能会保留；OpenSpec 生成文件仍会刷新。脚本不会自动提交或推送 Git，也不会自动归档 OpenSpec change。

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

这是**全局设置**，会影响其他项目的后续 OpenSpec 操作。脚本只读取该设置，不自动修改它。检查发生在全局 OpenSpec 安装/更新之后，失败不会回滚此前的安装。

### 旧项目缺少共享目录中的 OpenSpec 技能

查看脚本输出的缺失路径及修复提示。脚本会保留 `.codex/skills` 中的旧文件，不自动迁移或删除副本。已有文档里的 `CONTEXT.md` 指引也不会自动替换。

### 重复运行

可以补齐缺失文档及 Matt Pocock 技能，并重新执行检查。已有技能路径即使不完整或为悬空链接也会保留；缺少 `SKILL.md` 时最终检查会报错，需要手动处理。

如需更新某个已有技能，先保存自己的定制内容，再显式执行，例如：

```bash
npx --yes skills@latest add mattpocock/skills --skill tdd --agent codex --copy --yes
```

该命令会替换目标技能目录。脚本每次仍会更新全局 OpenSpec 和项目的 OpenSpec 生成文件，上游 `openspec update` 也可能执行配置迁移。

### OpenSpec 自定义 profile 缺少必需流程

已有项目在刷新前会检查全局 profile。若 `custom` 缺少 `propose`、`apply` 或 `archive`，脚本会停止，避免刷新时先删除这些必需技能再报告失败。通过 `openspec config` 补齐 workflows 或选择 `core` 后重跑；这属于全局设置，会影响其他项目。脚本不会自动修改这些设置，检查失败也不会回滚此前的全局安装。

## 验证范围

运行语法检查和回归测试（需 Bash、Node.js 和 Python 3）：

```bash
bash -n init-codex-project.sh
python3 -B -m unittest discover -s tests -v
```

回归测试在临时目录运行，使用 npm、npx、OpenSpec 替身，不安装工具。真实 OpenSpec 的验证版本及边界见 [CHANGELOG.md](CHANGELOG.md)；未进行完整联网安装验证。
