# Codex 项目初始化脚本更新记录

本记录只描述初始化脚本的变化；脚本生成的项目 `CHANGELOG.md` 用于记录各项目自身的变化。

## 2.2.0 — 2026-10-20

统一脚本：`init-codex-project.sh`。

### 变更

- 将 2.1.0 的配置检查、就绪状态、文档保护及领域文档指引合并到 `init-codex-project.sh`，删除 `init-codex-project-v2.1.0.sh`，后续只维护一个入口。
- 同步脚本版本、使用示例及 README，将失效的 `INIT-CODEX-PROJECT-CHANGELOG.md` 引用改为实际的 `CHANGELOG.md`。
- Matt Pocock 技能改为只安装缺失路径，保留已有定制。已有目录、文件或符号链接不自动覆盖；缺少 `SKILL.md` 时由最终检查报错。需要更新已有技能时，保存定制后手动执行对应安装命令。

### 修复

- 已有 OpenSpec 项目在刷新前检查全局 profile：允许 `core`，或包含 `propose`、`apply`、`archive` 的 `custom`；读取失败、未知 profile、无效或不完整的 workflows 均提前停止，防止必需技能被更新操作删除后才报错。
- 保留首次初始化的 `--profile core` 行为；脚本不自动修改全局 profile/workflows。检查仍在全局 OpenSpec 安装之后，失败不回滚此前的安装。

### 验证

- `bash -n init-codex-project.sh`、`git diff --check` 通过。
- 新增 `tests/test_init_codex_project.py`，11 项回归测试通过：覆盖首次初始化、重复运行保留定制技能和文档、仅补齐缺失技能、配置异常提前停止、兼容 custom profile、悬空技能链接保护。
- 本机 OpenSpec 1.14.1 的 5 个临时目录场景通过：首次初始化、core 重跑、不完整 custom 拦截、兼容 custom 重跑、commands delivery 拦截。确认被拦截时项目文件不变，正常重跑保留 Matt Pocock 定制技能及已有文档；兼容 custom 仍按全局配置移除未选择的非必需 OpenSpec 技能。
- 未执行全局 npm 升级或联网 Skills 安装：回归测试替代 npm、npx 和 OpenSpec，真实 OpenSpec 验证仅替代 npm、npx，并隔离全局配置与数据目录。

## 2.1.0 — 2026-10-03

当时发布脚本：`init-codex-project-v2.1.0.sh`，原版 `init-codex-project.sh`（2.0.0）保持不变。自 2.2.0 起两者已合并；以下为历史记录。

### 修复

- 将生成的领域文档指引及终端提示改为 `GLOSSARY.md` / `GLOSSARY-MAP.md`，与当前 Matt Pocock 技能约定一致；仍按需创建领域文档。
- 在 OpenSpec 初始化或刷新前检查 `delivery`。允许 `skills` / `both`；遇到 `commands`、未知值或读取失败时停止并提示原因，避免命令成功却没有生成技能。脚本不会修改全局 `delivery` 设置。
- 必需技能缺失、OpenSpec 项目不可读或必需文档检查失败时，返回非零退出码，并报告 `INITIALIZATION INCOMPLETE`。
- 文档检查区分缺失、非普通文件、不可读、扫描失败和占位内容；固定基础文件也纳入最终检查。已有悬空符号链接会保留并报错，不通过链接创建目标文件。
- 末尾占位符检查命令只扫描五份目标文档，避免匹配初始化脚本自身；说明 `grep` 退出码含义。

### 使用与兼容性

在目标项目根目录执行：

```bash
bash /path/to/init-codex-project-v2.1.0.sh
```

- 保留原版的全局 OpenSpec 安装/更新、项目 Skills 安装和“已有文档不覆盖”行为。
- `delivery` 检查在 OpenSpec 安装/更新之后、项目初始化之前执行；失败不代表此前的全局安装已回滚。
- 保留的 `openspec update` 调用可能执行上游配置迁移。实测 OpenSpec 1.12.0 会补写全局 `profile` / `workflows` 字段，`delivery` 保持不变。
- 退出码 `0` 表示初始化与检查完成。新生成的占位文档仍需填写，会显示 `INITIALIZED, NOT READY FOR DEVELOPMENT`；文档无占位标记且工具检查通过才显示 `READY FOR DEVELOPMENT`。该状态不代表项目构建或测试已经通过。
- 已有文档保留原内容；运行新版不会自动替换旧文档中的 `CONTEXT.md` 指引或迁移领域文档。

### 验证

- `bash -n` 语法检查通过。
- 临时目录中的 18 项模拟检查通过：覆盖首次初始化、重复运行保留文档、就绪状态、占位符扫描、delivery 检查、技能缺失、OpenSpec 读取失败、文档类型/缺失/读取异常等分支。
- 本机 OpenSpec 1.12.0 的 3 项配置检查通过：`both` / `skills` 可初始化及重复运行，`commands` 在项目初始化前停止。
- 原版脚本 SHA-256 未变；未执行全局 npm 升级或联网 Skills 安装，这两类命令在测试中由替身替代。

## 2.0.0 — 原有版本，发布日期未记录

脚本：`init-codex-project.sh`。

- 检查 Node.js，并安装/更新 OpenSpec。
- 使用共享 `.agents/skills` 目标初始化 OpenSpec，安装选定的 Matt Pocock 项目技能。
- 创建五份项目占位文档、`.editorconfig`、ADR 说明和 GitHub PR 模板。
- 输出工具检查与项目就绪报告。
