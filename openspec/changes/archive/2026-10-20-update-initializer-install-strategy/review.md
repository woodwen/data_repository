# Review：update-initializer-install-strategy

日期：2026-10-20。基线：`b54a5bd`。范围：该提交后的未提交脚本、测试、README、CHANGELOG 及新增 OpenSpec 文件。Standards 与 Spec 由两条独立审查线完成，确认同一项 Major，不重复计数为两个缺陷。

## Standards

发现 1 项 Major：Skills CLI 普通模式不能可靠表达逐技能安装失败，而脚本仅以退出码和最终文件存在判断完成，违反可验证完成标准。没有额外硬性规范违规，也没有需要增加抽象才能解决的代码异味。

修复：安装命令追加 `--json`，并说明固定 CLI 版本的退出码差异。增加两个针对实际失败行为的回归场景。独立复审通过，剩余 Critical/Major/Minor 均为 0。

## Spec

发现 1 项 Major（与 Standards 为同一问题）：安装失败时旧 `SKILL.md` 仍在，可能导致成功状态，违反“安装失败必须非零退出”和“来源中缺少任一要求技能必须报错”的要求。

固定 Skills CLI 1.7.4 的真实复现结果：

| 场景 | 普通模式 | JSON 模式 |
| --- | --- | --- |
| 只读目标阻止替换，旧文件仍在 | 退出 0，输出失败 | 退出 1 |
| 请求两个技能，来源仅含其中一个 | 退出 0，安装匹配项 | 退出 1，标识未匹配项 |

切换 JSON 模式后，脚本能立即停止并保留备份，不进入成功状态判断。Spec 独立复审通过，无剩余需求遗漏、越界行为或实现错误。

## 修复验证

- 新增旧文件残留回归测试在修复前失败；修复后通过。
- 全部 34 项回归测试通过；Spec 审查线独立重跑同样通过。
- Bash 语法、OpenSpec 1.14.3 单 change/全量 strict validation、`git diff --check` 通过。
- 使用原隔离集成环境再次执行完整 `--upgrade`，真实安装全部 9 个固定来源技能，备份保留升级前定制，锁文件 ref 正确。
- 完整升级日志：`/tmp/codex-strategy-integration-yvz5kvt6/review-json-upgrade.log`。
- 问题复现日志：`/tmp/skills-exit-review-_iajde2z/`、`/tmp/skills-selection-review-yd4hqorb/`。
- design、specs、tasks、CHANGELOG 和 verification 已同步。

## 结论

Standards 和 Spec 均通过；没有剩余 Critical 或 Major。可进入完成提交/归档流程。未提交、推送或归档，未升级用户全局工具。
