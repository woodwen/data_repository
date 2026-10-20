# M-1(fix): 合并初始化脚本并保护重复运行时的项目技能

背景:
- 2.0.0 与 2.1.0 两个入口并存；重复运行可能因全局 OpenSpec profile 删除必需技能，并覆盖已有 Matt Pocock 技能定制。

方案概述:
- 统一使用 init-codex-project.sh，版本更新为 2.2.0，在刷新前校验必需流程，并只补齐缺失的第三方技能。

实现改动:
- 合并 2.1.0 的 delivery、文档及就绪检查，删除带版本号的副本。
- 更新前验证全局 profile/workflows，阻止不兼容配置删除必需技能。
- 保留已有 Matt Pocock 技能路径和定制内容，复用必需技能列表进行安装与验证。
- 同步 README.md、CHANGELOG.md，新增 11 项隔离回归测试。

测试计划(UT):
- 通过 bash -n init-codex-project.sh。
- 通过 python3 -B -m unittest discover -s tests -v，共 11 项测试。
- 通过 git diff --check。
- 前一实施轮已验证本机 OpenSpec 1.14.1 的首次初始化、core 重跑、不完整 custom 拦截、兼容 custom 重跑及 commands 拦截，共 5 个临时目录场景。
- 未执行全局 npm 升级或联网 Skills 安装；测试使用替身或隔离的 OpenSpec 配置。

影响范围(建议手动测试范围):
- 使用旧版本号脚本路径的调用方需改用 init-codex-project.sh。
- 手动确认真实联网首次安装、旧项目重复运行及技能定制保留行为。
- OpenSpec 生成文件仍按全局配置刷新；已有 Matt Pocock 技能需要显式手动更新。
