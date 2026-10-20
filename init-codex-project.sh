#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Codex Project Initializer
# Version: 2.3.0
# Release date: 2026-10-20
# Update history: CHANGELOG.md
#
# Includes:
# - Node.js/OpenSpec checks
# - OpenSpec project setup via shared .agents/skills target
# - Matt Pocock project Skills
# - Project placeholder docs
# - .editorconfig
# - ADR documentation
# - GitHub PR template
# - Final project health report
#
# Usage:
#   chmod +x init-codex-project.sh
#   ./init-codex-project.sh
#
# Run this script from the repository root.
# ============================================================

SCRIPT_VERSION="2.3.0"
OPENSPEC_VERSION="1.14.3"
SKILLS_CLI_VERSION="1.7.4"
MATT_SKILLS_REF="5beb35b040e3de97e54fa9e386d7e42d15c295c2"
REQUIRED_MATT_SKILLS=(
  "setup-matt-pocock-skills"
  "grill-with-docs"
  "grilling"
  "domain-modeling"
  "codebase-design"
  "tdd"
  "diagnosing-bugs"
  "code-review"
  "writing-for-agents"
)
PLACEHOLDER_MARKER="PLACEHOLDER:REPLACE_ME"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

section() {
  echo ""
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

step() {
  echo ""
  echo "==> $1"
}

ok() {
  echo "  [OK] $1"
}

warn() {
  echo "  [WARN] $1"
}

info() {
  echo "  [INFO] $1"
}

fail() {
  echo "  [ERROR] $1" >&2
  exit 1
}

create_if_missing() {
  local file="$1"
  if [ -e "$file" ] || [ -L "$file" ]; then
    info "Skipped existing file: $file"
    return 1
  fi
  return 0
}

has_glob_match() {
  compgen -G "$1" >/dev/null 2>&1
}

# ------------------------------------------------------------
# Arguments and failure reporting
# ------------------------------------------------------------

MODE="initialize"
SHOW_HELP=0
PHASE="arguments"
BACKUP_DIR=""
BACKUP_COMPLETE=0
GLOBAL_INSTALL_ATTEMPTED=0
GLOBAL_INSTALL_COMPLETE=0

report_failure() {
  local status="$1"
  if [ "$status" -eq 0 ]; then
    return
  fi
  echo "  [ERROR] Failed during: $PHASE (exit $status). No automatic rollback was performed." >&2
  if [ "$GLOBAL_INSTALL_COMPLETE" -eq 1 ]; then
    echo "  [WARN] Global OpenSpec installation completed before this failure." >&2
  elif [ "$GLOBAL_INSTALL_ATTEMPTED" -eq 1 ]; then
    echo "  [WARN] Global OpenSpec installation was attempted and may have changed the npm prefix." >&2
  fi
  if [ -n "$BACKUP_DIR" ]; then
    echo "  [INFO] Backup: $BACKUP_DIR" >&2
    if [ "$BACKUP_COMPLETE" -eq 1 ]; then
      echo "  [INFO] Compare manifest.json and saved .agents/skills with the project; restore only listed paths after reviewing partial changes." >&2
      echo "  [INFO] Review skills-lock.json separately; it can include unrelated skills. See README for recovery steps." >&2
    else
      echo "  [WARN] Backup is incomplete; do not use it as a complete restore point." >&2
    fi
  fi
}
trap 'report_failure "$?"' EXIT

for arg in "$@"; do
  case "$arg" in
    --upgrade) MODE="upgrade" ;;
    --help) SHOW_HELP=1 ;;
    *) fail "Unknown argument: $arg. Use --help." ;;
  esac
done
if [ "$SHOW_HELP" -eq 1 ]; then
  cat <<'HELP'
Usage: bash init-codex-project.sh [--upgrade | --help]
Run from the target project root with Node.js >=22.20.0 and Git.
Default: install missing dependencies, reuse supported OpenSpec, preserve existing skills.
--upgrade: upgrade older OpenSpec to the pinned target and refresh the nine Matt Pocock skills after backup.
Newer OpenSpec is never downgraded. Backups remain in .init-codex-backups/.
HELP
  exit 0
fi

# ------------------------------------------------------------
# Preflight helpers
# ------------------------------------------------------------

compare_openspec_version() {
  node - "$1" "$OPENSPEC_VERSION" <<'VERSION_CHECK'
const [actual, target] = process.argv.slice(2);
if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(actual)) {
  console.error(`ERROR: Cannot parse stable OpenSpec version: ${actual}`);
  process.exit(1);
}
const a = actual.split(".").map(Number);
const b = target.split(".").map(Number);
let result = 0;
for (let i = 0; i < 3; i++) {
  if (a[i] !== b[i]) {
    result = a[i] < b[i] ? -1 : 1;
    break;
  }
}
console.log(result);
VERSION_CHECK
}

check_openspec_config() {
  if ! OPENSPEC_DELIVERY="$(openspec config get delivery)"; then
    fail "Cannot read OpenSpec delivery configuration. Resolve this with the installed CLI before upgrading."
  fi
  case "$OPENSPEC_DELIVERY" in
    skills|both) ;;
    commands)
      fail "OpenSpec delivery=commands cannot generate .agents/skills. Set delivery to skills or both (global setting), then rerun: openspec config set delivery both"
      ;;
    *) fail "Unsupported OpenSpec delivery value: $OPENSPEC_DELIVERY" ;;
  esac
  if [ -f "openspec/config.yaml" ]; then
    if ! OPENSPEC_PROFILE="$(openspec config get profile)"; then
      fail "Cannot read OpenSpec profile configuration. Resolve this with the installed CLI before upgrading."
    fi
    case "$OPENSPEC_PROFILE" in
      core) ;;
      custom)
        if ! OPENSPEC_WORKFLOWS="$(openspec config get workflows)"; then
          fail "Cannot read OpenSpec workflows configuration."
        fi
        if ! node - "$OPENSPEC_WORKFLOWS" <<'WORKFLOW_CHECK'
let workflows;
try {
  workflows = JSON.parse(process.argv[2]);
} catch {
  console.error("ERROR: OpenSpec workflows must be a JSON array.");
  process.exit(1);
}
if (!Array.isArray(workflows)) {
  console.error("ERROR: OpenSpec workflows must be a JSON array.");
  process.exit(1);
}
const missing = ["propose", "apply", "archive"].filter(name => !workflows.includes(name));
if (missing.length > 0) {
  console.error(`ERROR: OpenSpec custom profile is missing required workflows: ${missing.join(", ")}`);
  process.exit(1);
}
WORKFLOW_CHECK
        then
          fail "OpenSpec update skipped. Include propose, apply and archive in the global custom workflows, or choose the core profile, then rerun."
        fi
        ;;
      *) fail "Unsupported OpenSpec profile value: $OPENSPEC_PROFILE" ;;
    esac
  fi
}

prepare_skill_upgrade() {
  node - "$1" "$OPENSPEC_VERSION" "$SKILLS_CLI_VERSION" "$MATT_SKILLS_REF" "${REQUIRED_MATT_SKILLS[@]}" <<'BACKUP'
const fs = require("node:fs");
const path = require("node:path");
const [action, openspec, skillsCli, ref, ...names] = process.argv.slice(2);
function check(file, type) {
  let stat;
  try {
    stat = fs.lstatSync(file);
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
  if (stat.isSymbolicLink() || !(type === "directory" ? stat.isDirectory() : stat.isFile())) {
    throw new Error(`Unsupported upgrade path: ${file}. Resolve links or file types manually.`);
  }
  return true;
}
try {
  for (const dir of [".agents", ".agents/skills", ".init-codex-backups"]) check(dir, "directory");
  const skills = names.map(name => {
    const file = `.agents/skills/${name}`;
    return { name, path: file, existed: check(file, "directory") };
  });
  const lockFile = { path: "skills-lock.json", existed: check("skills-lock.json", "file") };
  if (lockFile.existed) {
    const lock = JSON.parse(fs.readFileSync(lockFile.path, "utf8"));
    if (lock?.version !== 1 || !lock.skills || typeof lock.skills !== "object" || Array.isArray(lock.skills)) {
      throw new Error("Unsupported skills-lock.json format; review it before upgrading.");
    }
    for (const name of names) {
      if (Object.hasOwn(lock.skills, name) && lock.skills[name]?.source !== "mattpocock/skills") {
        throw new Error(`Skill source conflict for ${name}; preserve the existing skill and resolve ownership manually.`);
      }
    }
  }
  if (action === "backup") {
    const base = path.resolve(".init-codex-backups");
    fs.mkdirSync(base, { recursive: true });
    const backup = fs.mkdtempSync(path.join(base, "run-"));
    console.log(backup);
    for (const skill of skills.filter(skill => skill.existed)) {
      fs.mkdirSync(path.dirname(path.join(backup, skill.path)), { recursive: true });
      fs.cpSync(skill.path, path.join(backup, skill.path), {
        recursive: true, dereference: false, verbatimSymlinks: true, preserveTimestamps: true,
        filter(source) {
          const stat = fs.lstatSync(source);
          if (!stat.isFile() && !stat.isDirectory() && !stat.isSymbolicLink()) {
            throw new Error(`Unsupported backup entry: ${source}`);
          }
          return true;
        }
      });
    }
    if (lockFile.existed) fs.copyFileSync(lockFile.path, path.join(backup, lockFile.path));
    fs.writeFileSync(path.join(backup, "manifest.json"), JSON.stringify({
      project: process.cwd(), createdAt: new Date().toISOString(),
      targets: { openspec, skillsCli, mattSkillsRef: ref }, skills, lockFile
    }, null, 2) + "\n");
  }
} catch (error) {
  console.error(`ERROR: ${error.message}`);
  process.exit(1);
}
BACKUP
}

# ------------------------------------------------------------
# 1. Safety / prerequisites
# ------------------------------------------------------------

section "Codex Project Initializer v${SCRIPT_VERSION}"
echo "Project: $(pwd)"
echo "Mode: $MODE"
info "Targets: OpenSpec $OPENSPEC_VERSION; Skills CLI $SKILLS_CLI_VERSION; Matt Pocock $MATT_SKILLS_REF"
PHASE="environment preflight"
step "[1/9] Checking environment"

if [ "$(pwd)" = "/" ] || [ "$(pwd)" = "$HOME" ]; then
  fail "Run this script from a project directory, not / or your home directory."
fi
for cmd in node npm npx git mkdir cat grep; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "Required command not found: $cmd"
  fi
done
node <<'NODE_CHECK'
const [major, minor] = process.versions.node.split(".").map(Number);
if (!(major > 22 || (major === 22 && minor >= 20))) {
  console.error(`ERROR: Node.js ${process.versions.node} is too old. Skills CLI requires Node.js >=22.20.0.`);
  process.exit(1);
}
NODE_CHECK
ok "Node.js $(node --version)"
ok "npm $(npm --version)"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ok "Git repository detected"
else
  warn "Current directory is not a Git repository yet"
fi

PHASE="dependency and configuration preflight"
OPENSPEC_BEFORE="missing"
INSTALL_OPENSPEC=1
if command -v openspec >/dev/null 2>&1; then
  if ! OPENSPEC_BEFORE="$(openspec --version)"; then
    fail "Cannot read installed OpenSpec version."
  fi
  VERSION_COMPARISON="$(compare_openspec_version "$OPENSPEC_BEFORE")"
  if [ "$VERSION_COMPARISON" -lt 0 ]; then
    if [ "$MODE" != "upgrade" ]; then
      fail "OpenSpec $OPENSPEC_BEFORE is older than $OPENSPEC_VERSION. Rerun with --upgrade."
    fi
  else
    INSTALL_OPENSPEC=0
  fi
  check_openspec_config
fi
info "OpenSpec before: $OPENSPEC_BEFORE"

if [ "$MODE" = "upgrade" ]; then
  prepare_skill_upgrade check
  PHASE="skill backup"
  BACKUP_DIR="$(prepare_skill_upgrade backup)"
  BACKUP_COMPLETE=1
  info "Backup: $BACKUP_DIR"
fi

# ------------------------------------------------------------
# 2. Install / reuse OpenSpec
# ------------------------------------------------------------

PHASE="global OpenSpec installation"
step "[2/9] Installing / reusing OpenSpec"
if [ "$INSTALL_OPENSPEC" -eq 1 ]; then
  GLOBAL_INSTALL_ATTEMPTED=1
  npm install -g "@fission-ai/openspec@${OPENSPEC_VERSION}"
  GLOBAL_INSTALL_COMPLETE=1
  hash -r
  if ! command -v openspec >/dev/null 2>&1; then
    fail "OpenSpec installed but 'openspec' is not available on PATH."
  fi
  OPENSPEC_AFTER="$(openspec --version)"
  if [ "$OPENSPEC_AFTER" != "$OPENSPEC_VERSION" ]; then
    fail "Expected OpenSpec $OPENSPEC_VERSION after installation, got $OPENSPEC_AFTER. Check npm prefix and PATH."
  fi
else
  OPENSPEC_AFTER="$OPENSPEC_BEFORE"
  info "Reusing OpenSpec $OPENSPEC_AFTER; no global installation or downgrade"
fi
ok "OpenSpec: $OPENSPEC_BEFORE -> $OPENSPEC_AFTER"

# ------------------------------------------------------------
# 3. Initialize / refresh OpenSpec
# ------------------------------------------------------------

PHASE="OpenSpec configuration recheck"
check_openspec_config
PHASE="project OpenSpec initialization / refresh"
step "[3/9] Initializing OpenSpec"
if [ -f "openspec/config.yaml" ]; then
  info "Refreshing generated OpenSpec files"
  openspec update . --force
else
  openspec init . \
    --tools agents \
    --profile core \
    --language "简体中文" \
    --no-animation \
    --no-copilot-cloud
fi

if has_glob_match ".agents/skills/openspec-*/SKILL.md"; then
  ok "OpenSpec skills found under .agents/skills"
else
  warn "No OpenSpec skills found under .agents/skills"
  warn "For an existing project, run:"
  echo "       openspec init . --tools agents --profile core --force --no-animation --no-copilot-cloud"
fi

# ------------------------------------------------------------
# 4. Install / refresh Matt Pocock project Skills
# ------------------------------------------------------------

PHASE="Matt Pocock skill installation"
step "[4/9] Installing Matt Pocock project Skills"
MATT_SKILL_ARGS=()
for skill in "${REQUIRED_MATT_SKILLS[@]}"; do
  skill_dir=".agents/skills/${skill}"
  if [ "$MODE" = "upgrade" ]; then
    info "Selected for refresh/install: $skill_dir"
    MATT_SKILL_ARGS+=(--skill "$skill")
  elif [ -e "$skill_dir" ] || [ -L "$skill_dir" ]; then
    info "Preserved existing skill path: $skill_dir"
  else
    info "Selected for installation: $skill_dir"
    MATT_SKILL_ARGS+=(--skill "$skill")
  fi
done
if [ "${#MATT_SKILL_ARGS[@]}" -gt 0 ]; then
  # Skills CLI 1.7.4 only reports per-skill failures as nonzero in JSON mode.
  npx --yes "skills@${SKILLS_CLI_VERSION}" add "https://github.com/mattpocock/skills/tree/${MATT_SKILLS_REF}" \
    "${MATT_SKILL_ARGS[@]}" \
    --agent codex \
    --copy \
    --yes \
    --json
  ok "Matt Pocock Skills install command completed"
else
  info "No missing Matt Pocock skill paths to install"
fi

PHASE="project documents"

# ------------------------------------------------------------
# 5. Create directories
# ------------------------------------------------------------

step "[5/9] Creating project documentation directories"

mkdir -p docs/adr
mkdir -p .github

ok "docs/adr"
ok ".github"

# ------------------------------------------------------------
# 6. Create placeholder project docs
# ------------------------------------------------------------

step "[6/9] Creating placeholder project documents"

# -----------------------------
# AGENTS.md
# -----------------------------

if create_if_missing "AGENTS.md"; then
  cat > AGENTS.md <<'EOF'
# AGENTS.md

> PLACEHOLDER:REPLACE_ME
>
> 本文件为项目初始化占位文件。
> 正式开发前，请基于当前仓库真实实现替换所有占位内容。

## 项目定位

- 项目名称：`<PROJECT_NAME>`
- 项目类型：`<WEB / DESKTOP / MOBILE / SERVICE / GAME / OTHER>`
- 核心目标：`<PROJECT_GOAL>`
- 当前阶段：`<FOUNDATION / MVP / DEVELOPMENT / MAINTENANCE>`

相关文档：

- `README.md`
- `docs/PROJECT.md`
- `docs/ARCHITECTURE.md`
- `docs/adr/`
- `CHANGELOG.md`

## 技术栈

- Language：`<LANGUAGE>`
- Framework：`<FRAMEWORK>`
- UI：`<UI_FRAMEWORK>`
- State Management：`<STATE_MANAGEMENT>`
- Build Tool：`<BUILD_TOOL>`
- Package Manager：`<PACKAGE_MANAGER>`
- Test：`<TEST_FRAMEWORK>`

## 架构约束

当前项目采用：

`<ARCHITECTURE，例如 MVVM / Clean Architecture / Feature-first>`

基本要求：

- 保持模块职责单一。
- 优先复用现有模块和抽象，不重复创建相似实现。
- UI、状态、领域逻辑和基础设施保持清晰边界。
- 新增大型依赖前先说明原因和影响范围。
- 不为了局部需求进行无关的大规模重构。
- 重大且难以逆转的架构决策记录到 `docs/adr/`。

详细架构：

`docs/ARCHITECTURE.md`

## Domain 文档

Matt Pocock 的 `grill-with-docs` / `domain-modeling` 会在需要时维护：

- `GLOSSARY.md`
- `GLOSSARY-MAP.md`（多 bounded-context 项目按需）
- `docs/adr/`

不要仅为了“目录完整”创建空的 `GLOSSARY.md`。

## OpenSpec 工作流

非简单修改优先通过 OpenSpec 管理。

推荐流程：

1. 明确需求。
2. 复杂或模糊需求先使用 `$grill-with-docs`。
3. 使用 `$openspec-propose` 创建 change。
4. Review proposal / design / specs / tasks。
5. 人工确认方案。
6. 使用 `$openspec-apply-change` 实施。
7. 核心逻辑和 Bug 修复优先遵循 `$tdd`。
8. 完成后使用 `$code-review`。
9. 执行项目验证命令。
10. 人工 Review。
11. 最后归档 OpenSpec change。

要求：

- 需求、影响范围或技术方案不明确时，不进行大范围修改。
- OpenSpec change 未确认前，不提前实施复杂需求。
- 实现应对应当前 change 的 specs/tasks。
- 不主动扩大 change 范围。
- 不自动 archive，除非用户明确要求。

## Bug 处理

复杂 Bug 优先使用：

`$diagnosing-bugs`

遵循：

复现 → 最小化 → 假设 → 验证/插桩 → 修复 → 回归测试

禁止：

- 未确认根因就进行大量随机修改。
- 为绕过 Bug 引入无关 fallback。
- 删除或弱化测试来让 CI 通过。

## TDD

新增核心业务逻辑和 Bug 修复优先使用：

`$tdd`

基本过程：

RED → GREEN → REFACTOR

测试应覆盖行为，不要过度绑定内部实现。

## Code Review

完成实现后使用：

`$code-review`

重点检查：

- 是否符合需求和 OpenSpec。
- 是否存在不必要复杂度。
- 是否破坏已有模块边界。
- 是否存在重复实现。
- 是否遗漏异常路径。
- 是否存在测试缺失。
- 是否存在无关修改。

## 项目命令

安装依赖：

```bash
<INSTALL_COMMAND>
```

启动开发环境：

```bash
<DEV_COMMAND>
```

Lint / Type Check：

```bash
<LINT_OR_TYPECHECK_COMMAND>
```

测试：

```bash
<TEST_COMMAND>
```

构建：

```bash
<BUILD_COMMAND>
```

其他验证：

```bash
<OTHER_VALIDATION_COMMANDS>
```

## 完成标准

任务完成前至少确认：

- [ ] 实现符合当前需求 / OpenSpec
- [ ] 没有无关修改
- [ ] 测试通过
- [ ] Lint / Type Check 通过
- [ ] Build 通过
- [ ] `git diff --check` 通过
- [ ] 完成 `$code-review`
- [ ] 完成人工 Review

## Git

默认：

- 不自动 push。
- 不自动 archive OpenSpec change。
- 不自动修改无关文件。
- 不自动创建无关的大范围重构。

Commit / PR 规则：

`<COMMIT_AND_PR_RULES>`

## 项目特殊规则

`<PROJECT_SPECIFIC_RULES>`

EOF
  ok "Created AGENTS.md"
fi

# -----------------------------
# README.md
# -----------------------------

if create_if_missing "README.md"; then
  cat > README.md <<'EOF'
# <PROJECT_NAME>

> PLACEHOLDER:REPLACE_ME
>
> 本 README 由项目初始化脚本生成。
> 正式开发前请根据项目真实情况替换所有占位内容。

`<一句话说明项目是什么，以及解决什么问题>`

## 项目简介

`<PROJECT_DESCRIPTION>`

## Features

当前已实现：

- `<FEATURE_1>`
- `<FEATURE_2>`

正在开发：

- `<IN_PROGRESS_FEATURE>`

计划实现：

- `<PLANNED_FEATURE>`

## Tech Stack

| 类型 | 技术 |
|---|---|
| Language | `<LANGUAGE>` |
| Framework | `<FRAMEWORK>` |
| UI | `<UI_FRAMEWORK>` |
| State Management | `<STATE_MANAGEMENT>` |
| Router | `<ROUTER>` |
| Network | `<NETWORK>` |
| Storage | `<STORAGE>` |
| Test | `<TEST_FRAMEWORK>` |
| Build | `<BUILD_TOOL>` |
| Package Manager | `<PACKAGE_MANAGER>` |

## Getting Started

### Requirements

- `<REQUIREMENT_1>`
- `<REQUIREMENT_2>`

### Install

```bash
<INSTALL_COMMAND>
```

### Development

```bash
<DEV_COMMAND>
```

### Test

```bash
<TEST_COMMAND>
```

### Lint / Type Check

```bash
<LINT_OR_TYPECHECK_COMMAND>
```

### Build

```bash
<BUILD_COMMAND>
```

## Project Structure

```text
<PROJECT_NAME>/
├── .agents/
│   └── skills/
├── .github/
│   └── PULL_REQUEST_TEMPLATE.md
├── docs/
│   ├── adr/
│   ├── PROJECT.md
│   └── ARCHITECTURE.md
├── openspec/
│   ├── changes/
│   └── specs/
├── <SOURCE_DIRECTORY>/
├── AGENTS.md
├── CHANGELOG.md
└── README.md
```

请根据实际项目结构调整。

## Development Workflow

本项目使用：

- Codex
- OpenSpec
- Matt Pocock Skills
- TDD
- Code Review

推荐流程：

```text
需求
 ↓
$grill-with-docs
 ↓
$openspec-propose
 ↓
方案 Review
 ↓
$openspec-apply-change
 ↓
$tdd
 ↓
$code-review
 ↓
人工 Review + 验证
 ↓
归档 OpenSpec Change
```

详细规则：

- Agent 开发规则：`AGENTS.md`
- 产品范围：`docs/PROJECT.md`
- 技术架构：`docs/ARCHITECTURE.md`
- 架构决策：`docs/adr/`
- 版本变化：`CHANGELOG.md`

## OpenSpec

查看当前 changes：

```bash
openspec list
```

严格验证：

```bash
openspec validate --all --strict
```

## Roadmap

这里只保留高层里程碑，不维护细粒度 TODO。

- `<MILESTONE_1>`
- `<MILESTONE_2>`

具体需求、任务和变更统一通过 OpenSpec 管理。

## Contributing

`<CONTRIBUTING_RULES_OR_LINK>`

## License

`<LICENSE_OR_PRIVATE>`

EOF
  ok "Created README.md"
fi

# -----------------------------
# CHANGELOG.md
# -----------------------------

if create_if_missing "CHANGELOG.md"; then
  cat > CHANGELOG.md <<'EOF'
# Changelog

> PLACEHOLDER:REPLACE_ME
>
> 本文件由项目初始化脚本生成。
> 请基于当前仓库真实历史整理 [Unreleased]，不要伪造历史版本或日期。

记录本项目的重要版本变化。

## [Unreleased]

### Added

- 初始化项目工程化文档结构。
- 初始化 OpenSpec。
- 初始化 Codex 项目 Skills。

### Changed

- 暂无。

### Fixed

- 暂无。

### Removed

- 暂无。

<!--
后续版本建议：

## [0.2.0] - YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Fixed
- ...

### Removed
- ...
-->

EOF
  ok "Created CHANGELOG.md"
fi

# -----------------------------
# docs/PROJECT.md
# -----------------------------

if create_if_missing "docs/PROJECT.md"; then
  cat > docs/PROJECT.md <<'EOF'
# Project

> PLACEHOLDER:REPLACE_ME
>
> 请在正式开发前基于当前仓库真实状态补充本文件。

## 项目名称

`<PROJECT_NAME>`

## 项目简介

`<一句话描述项目是什么，以及解决什么问题>`

## 背景

`<WHY_THIS_PROJECT_EXISTS>`

## 目标用户

- `<USER_TYPE_1>`
- `<USER_TYPE_2>`

## 核心目标

1. `<GOAL_1>`
2. `<GOAL_2>`
3. `<GOAL_3>`

## 核心功能

### `<FEATURE_OR_CAPABILITY_1>`

`<DESCRIPTION>`

### `<FEATURE_OR_CAPABILITY_2>`

`<DESCRIPTION>`

## 当前阶段

`<FOUNDATION / MVP / DEVELOPMENT / PRODUCTION>`

当前已完成：

- `<DONE_1>`
- `<DONE_2>`

正在开发：

- `<IN_PROGRESS_1>`

尚未实现：

- `<NOT_IMPLEMENTED_1>`
- `<NOT_IMPLEMENTED_2>`

## Scope

本阶段包含：

- `<IN_SCOPE_1>`
- `<IN_SCOPE_2>`

本阶段不包含：

- `<OUT_OF_SCOPE_1>`
- `<OUT_OF_SCOPE_2>`

## Non-goals

明确不做：

- `<NON_GOAL_1>`
- `<NON_GOAL_2>`

## 产品原则

- `<PRINCIPLE_1>`
- `<PRINCIPLE_2>`

## 关键约束

- `<CONSTRAINT_1>`
- `<CONSTRAINT_2>`

EOF
  ok "Created docs/PROJECT.md"
fi

# -----------------------------
# docs/ARCHITECTURE.md
# -----------------------------

if create_if_missing "docs/ARCHITECTURE.md"; then
  cat > docs/ARCHITECTURE.md <<'EOF'
# Architecture

> PLACEHOLDER:REPLACE_ME
>
> 请根据当前项目真实架构替换本文件，不要描述尚不存在的模块。

## 架构概览

项目采用：

`<MVVM / Clean Architecture / Layered / Feature-first / Other>`

架构目标：

- 清晰的模块边界
- 可测试
- 控制模块耦合
- 避免业务逻辑散落在 UI
- 让基础设施实现可替换

## 技术栈

| 类型 | 技术 |
|---|---|
| Language | `<LANGUAGE>` |
| Framework | `<FRAMEWORK>` |
| UI | `<UI>` |
| State | `<STATE>` |
| Router | `<ROUTER>` |
| Network | `<NETWORK>` |
| Storage | `<STORAGE>` |
| Test | `<TEST>` |
| Build | `<BUILD>` |

## 真实目录结构

```text
<PROJECT_ROOT>/
├── ...
├── ...
└── ...
```

## 模块边界

### `<MODULE_1>`

职责：

`<DESCRIPTION>`

不负责：

`<DESCRIPTION>`

### `<MODULE_2>`

职责：

`<DESCRIPTION>`

不负责：

`<DESCRIPTION>`

## 依赖方向

根据实际项目修改：

```text
UI
 ↓
Application / ViewModel
 ↓
Domain
 ↓
Infrastructure
```

原则：

- 上层优先依赖明确接口。
- 基础设施实现不要反向污染领域模型。
- UI 不直接承担复杂业务逻辑。
- 跨模块依赖通过明确边界完成。

## 数据流

根据实际项目修改：

```text
User Action
   ↓
<State / ViewModel>
   ↓
<Use Case / Service>
   ↓
<Repository>
   ↓
<API / Storage>
```

## 状态管理

`<STATE_MANAGEMENT_RULES>`

## 错误处理

`<ERROR_HANDLING_RULES>`

## 日志

`<LOGGING_RULES>`

## 测试策略

### Unit Test

`<RULES>`

### Integration Test

`<RULES>`

### UI / E2E Test

`<RULES>`

## 性能与兼容性

- `<PERFORMANCE_OR_COMPAT_RULE_1>`
- `<PERFORMANCE_OR_COMPAT_RULE_2>`

## 禁止事项

- 不跨层直接访问不应访问的基础设施。
- 不复制已有领域模型。
- 不为了一个调用者创建无意义抽象。
- 不在没有明确收益时引入新的全局状态。
- 不进行与当前 change 无关的大范围重构。

## Architecture Decision Records

重大且难以逆转的技术决策记录到：

`docs/adr/`

EOF
  ok "Created docs/ARCHITECTURE.md"
fi

# ------------------------------------------------------------
# 7. Create fixed project infrastructure files
# ------------------------------------------------------------

step "[7/9] Creating fixed project infrastructure files"

# -----------------------------
# .editorconfig
# -----------------------------

if create_if_missing ".editorconfig"; then
  cat > .editorconfig <<'EOF'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.md]
trim_trailing_whitespace = false

[*.{yml,yaml}]
indent_style = space
indent_size = 2

[*.json]
indent_style = space
indent_size = 2
EOF
  ok "Created .editorconfig"
fi

# -----------------------------
# docs/adr/README.md
# -----------------------------

if create_if_missing "docs/adr/README.md"; then
  cat > docs/adr/README.md <<'EOF'
# Architecture Decision Records

本目录记录重要且难以逆转的技术决策。

Matt Pocock 的 `grill-with-docs` / `domain-modeling` 也可以在决策真正形成时维护 ADR。

## 何时创建 ADR

以下情况通常值得创建：

- 引入或替换核心框架
- 更换状态管理方案
- 调整整体架构或模块边界
- 引入重要基础设施
- 数据模型发生重大变化
- API / IPC / 持久化协议发生重大变化
- 作出具有长期影响的性能、兼容性或安全决策

可轻易回滚、没有明显 trade-off 的普通实现选择，不需要 ADR。

## 命名

```text
0001-use-mvvm.md
0002-use-local-mock-repository.md
```

## 模板

```markdown
# ADR-XXXX: <Title>

## Status

Accepted

## Context

为什么需要做这个决策。

## Decision

最终决定。

## Alternatives

考虑过哪些主要方案。

## Consequences

收益、代价、限制和后续影响。
```
EOF
  ok "Created docs/adr/README.md"
fi

# -----------------------------
# .github/PULL_REQUEST_TEMPLATE.md
# -----------------------------

if create_if_missing ".github/PULL_REQUEST_TEMPLATE.md"; then
  cat > .github/PULL_REQUEST_TEMPLATE.md <<'EOF'
## Summary

<!-- 本次修改解决什么问题？ -->

## OpenSpec

OpenSpec Change:

`<change-id / N/A>`

## Changes

- 
- 
- 

## Validation

- [ ] Tests
- [ ] Lint / Type Check
- [ ] Build
- [ ] `git diff --check`
- [ ] `openspec validate <change-id> --strict`（有 change 时）
- [ ] `openspec validate --all --strict`

## Review

- [ ] 已完成 `$code-review`
- [ ] 已人工 Review
- [ ] 无无关修改

## Screenshots / Demo

<!-- UI 变更时提供，否则填写 N/A -->

N/A
EOF
  ok "Created .github/PULL_REQUEST_TEMPLATE.md"
fi

# ------------------------------------------------------------
# 8. Verification
# ------------------------------------------------------------

PHASE="tooling verification"
step "[8/9] Verifying OpenSpec and Skills"

OPEN_SPEC_OK=1
MATT_SKILLS_OK=1

if openspec list >/dev/null 2>&1; then
  ok "OpenSpec project is readable"
else
  warn "OpenSpec project check failed: openspec list"
  OPEN_SPEC_OK=0
fi

REQUIRED_OPENSPEC_SKILLS=(
  "openspec-propose"
  "openspec-apply-change"
  "openspec-archive-change"
)

for skill in "${REQUIRED_OPENSPEC_SKILLS[@]}"; do
  if [ -f ".agents/skills/${skill}/SKILL.md" ]; then
    ok ".agents/skills/${skill}"
  else
    warn "Missing OpenSpec skill: .agents/skills/${skill}/SKILL.md"
    OPEN_SPEC_OK=0
  fi
done

for skill in "${REQUIRED_MATT_SKILLS[@]}"; do
  if [ -f ".agents/skills/${skill}/SKILL.md" ]; then
    ok ".agents/skills/${skill}"
  else
    warn "Missing Matt Pocock skill: .agents/skills/${skill}/SKILL.md"
    MATT_SKILLS_OK=0
  fi
done

if has_glob_match ".codex/skills/openspec-*/SKILL.md"; then
  warn "OpenSpec skills also exist under .codex/skills"
  warn "This script does not delete them automatically."
  warn "After confirming .agents/skills versions work, consider removing duplicate OpenSpec skill copies."
fi

# ------------------------------------------------------------
# 9. Placeholder / readiness report
# ------------------------------------------------------------

PHASE="readiness verification"
step "[9/9] Project readiness report"

PLACEHOLDER_COUNT=0
DOCUMENTS_OK=1

check_placeholder() {
  local file="$1"
  local description="$2"

  local grep_status

  if [ ! -e "$file" ] && [ ! -L "$file" ]; then
    printf "  [MISSING]     %-28s\n" "$file"
    DOCUMENTS_OK=0
  elif [ ! -f "$file" ] || [ ! -r "$file" ]; then
    printf "  [INVALID]     %-28s Expected a readable regular file\n" "$file"
    DOCUMENTS_OK=0
  elif grep -q "$PLACEHOLDER_MARKER" "$file"; then
    printf "  [PLACEHOLDER] %-28s %s\n" "$file" "$description"
    PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT + 1))
  else
    grep_status=$?
    if [ "$grep_status" -eq 1 ]; then
      printf "  [READY]       %-28s\n" "$file"
    else
      printf "  [INVALID]     %-28s Placeholder scan failed\n" "$file"
      DOCUMENTS_OK=0
    fi
  fi
}

echo ""
echo "Project documents:"
check_placeholder "AGENTS.md" "Agent 规则、真实命令、技术栈和项目约束"
check_placeholder "README.md" "项目入口、功能、技术栈、启动方式"
check_placeholder "CHANGELOG.md" "基于真实历史整理 Unreleased"
check_placeholder "docs/PROJECT.md" "产品定位、Scope、Non-goals、当前阶段"
check_placeholder "docs/ARCHITECTURE.md" "真实架构、目录、模块边界、数据流"

echo ""
echo "Fixed infrastructure:"

for file in \
  ".editorconfig" \
  "docs/adr/README.md" \
  ".github/PULL_REQUEST_TEMPLATE.md"
do
  if [ -f "$file" ] && [ -r "$file" ]; then
    printf "  [READY]       %s\n" "$file"
  elif [ -e "$file" ] || [ -L "$file" ]; then
    printf "  [INVALID]     %s Expected a readable regular file\n" "$file"
    DOCUMENTS_OK=0
  else
    printf "  [MISSING]     %s\n" "$file"
    DOCUMENTS_OK=0
  fi
done

echo ""
echo "Optional project files:"

for file in "LICENSE" "CONTRIBUTING.md" ".env.example"; do
  if [ -f "$file" ]; then
    printf "  [PRESENT]     %s\n" "$file"
  else
    printf "  [OPTIONAL]    %s\n" "$file"
  fi
done

echo ""
echo "Notes:"
echo "  - GLOSSARY.md is intentionally not pre-created."
echo "    Let grill-with-docs/domain-modeling create or maintain it when domain terms are resolved."
echo "  - LICENSE should only be added after you choose the actual license."
echo "  - .env.example is useful only when the project actually has environment variables."
echo "  - CONTRIBUTING.md is mainly useful for open-source or multi-contributor projects."

section "Initialization Result"

if [ "$OPEN_SPEC_OK" -eq 1 ]; then
  ok "OpenSpec"
else
  warn "OpenSpec needs attention"
fi

if [ "$MATT_SKILLS_OK" -eq 1 ]; then
  ok "Matt Pocock Skills"
else
  warn "Matt Pocock Skills need attention"
fi

echo ""
if [ "$OPEN_SPEC_OK" -ne 1 ] || [ "$MATT_SKILLS_OK" -ne 1 ] || [ "$DOCUMENTS_OK" -ne 1 ]; then
  echo "STATUS: INITIALIZATION INCOMPLETE"
  fail "Required tooling or documents failed verification. Resolve the warnings above and rerun."
elif [ "$PLACEHOLDER_COUNT" -gt 0 ]; then
  echo "STATUS: INITIALIZED, NOT READY FOR DEVELOPMENT"
  echo ""
  echo "${PLACEHOLDER_COUNT} placeholder document(s) still need completion."
else
  echo "STATUS: READY FOR DEVELOPMENT"
fi

echo ""
echo "Recommended next steps:"
echo ""
echo '  1. Open/restart Codex in this repository.'
echo '  2. Run: $setup-matt-pocock-skills'
echo '  3. Ask Codex to complete the five PLACEHOLDER:REPLACE_ME documents.'
echo '  4. Verify no placeholders remain:'
echo '       grep -n "PLACEHOLDER:REPLACE_ME" AGENTS.md README.md CHANGELOG.md docs/PROJECT.md docs/ARCHITECTURE.md'
echo '       # Exit 1 with no output means no markers remain; exit 2 indicates an error.'
echo '  5. Start complex requirement discovery with: $grill-with-docs'
echo '  6. Create the OpenSpec change with: $openspec-propose'
echo ""
