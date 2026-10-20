# M-2(feat): 固定初始化依赖并支持备份后显式升级

OpenSpec Change: update-initializer-install-strategy
版本: 2.2.0 -> 2.3.0（沿用用户确认的方案目标）

背景:
- 原脚本每次安装浮动版本 OpenSpec，已有 Matt Pocock 技能却始终跳过，缺少一致且可恢复的升级入口。
- Skills CLI 1.7.4 要求 Node.js >=22.20.0，普通输出模式还可能将逐技能安装失败报告为成功。

方案概述:
- 固定工具及技能来源，默认保留已有内容，通过 --upgrade 显式备份并升级；保持项目级复制安装和原有 9 个技能。

实现改动:
- 固定 OpenSpec 1.14.3、Skills CLI 1.7.4 和 Matt Pocock 提交 5beb35b040e3de97e54fa9e386d7e42d15c295c2。
- 提前校验 Node.js、Git、OpenSpec 版本及配置；默认拒绝旧版 OpenSpec，保留更高版本不降级。
- 升级前保存技能、锁文件及清单，拒绝异常路径、来源冲突和不完整备份，分阶段报告失败与恢复位置。
- 使用 Skills CLI --json，确保逐技能失败和部分来源缺失非零退出。
- 同步 README、CHANGELOG、回归测试；归档 OpenSpec change 并生成正式能力规范。

测试计划(UT):
- bash -n init-codex-project.sh 通过。
- python3 -B -m unittest discover -s tests -v：34 项通过。
- OpenSpec 1.14.3 归档前后 strict validation、git diff --check 及未跟踪文件空白检查通过。
- 实施及 review 阶段已完成隔离真实安装、默认重跑、显式升级、配置拦截、固定来源与备份验证。
- review 的 Major 已修复，Standards 与 Spec 双轴复审通过；真实 CLI 已复现并验证两类失败退出码。

影响范围(建议手动测试范围):
- 运行环境需 Node.js >=22.20.0 和 Git；脚本不自动升级 Node.js。
- 升级会替换受管理技能，定制保存在 .init-codex-backups，需按 README 比较恢复。
- 全局 npm 安装与项目刷新不具备事务回滚，失败时检查阶段及备份。
- 联网测试均在临时 prefix、项目和配置目录内进行；用户现有全局工具与技能未升级。
