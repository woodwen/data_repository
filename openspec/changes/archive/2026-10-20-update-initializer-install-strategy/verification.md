# 实施验收记录

日期：2026-10-20。脚本版本：2.3.0。

## 固定依赖

- OpenSpec：1.14.3；npm 包和 CLI 参数均已核实。
- Skills CLI：1.7.4；npm 包要求 Node.js >=22.20.0。
- Matt Pocock：`5beb35b040e3de97e54fa9e386d7e42d15c295c2`，通过 git ls-remote 和临时 clone HEAD 交叉核对。
- 固定 tree URL 已通过 Skills CLI 1.7.4 实测，成功安装原有 9 个技能，项目锁文件全部记录上述 ref。

## 自动化检查

| 检查 | 结果 |
| --- | --- |
| `bash -n init-codex-project.sh` | 通过 |
| `python3 -B -m unittest discover -s tests -v` | 34 项通过 |
| `openspec validate update-initializer-install-strategy --strict` | 通过，使用临时安装的 1.14.3 |
| `openspec validate --all --strict` | 1 项通过，0 失败 |
| `git diff --check` | 通过 |
| 未跟踪方案文件空白检查、README 本地链接检查 | 通过 |

新增行为在旧实现上先出现失败，再通过新实现。保留原有 11 项测试，增补运行时边界、参数、工具版本、升级范围、配置复查、备份和故障报告。最后针对 Node.js 复制时可能跳过的 FIFO 添加显式类型拒绝，并确认失败备份不生成完整清单、不执行后续安装；目录内部链接按链接保存。

## 真实联网集成

使用机器上已有的 Node.js 24.21.0，通过临时 PATH 选择；不修改默认 Node.js。npm prefix、npm cache、项目目录以及 XDG_CONFIG_HOME、XDG_DATA_HOME、XDG_CACHE_HOME、XDG_STATE_HOME 均指向临时目录，npm 用户配置读取 `/dev/null`。未改写 HOME 或 CODEX_HOME。关闭测试中的工具遥测和 Node 编译缓存。

| 场景 | 核实结果 |
| --- | --- |
| 首次安装 | 临时 prefix 缺少 OpenSpec 时安装 1.14.3；项目安装 9 个固定来源技能 |
| 默认重跑 | 项目快照保持不变；定制 tdd、AGENTS.md、不相关技能及锁文件保持 |
| 显式技能升级 | 定制内容与原锁文件完整备份；技能恢复为固定来源内容；无关技能与条目保留 |
| 已有旧 CLI，默认运行 | 临时 prefix 安装 1.14.1 作为前置条件；默认运行被拦截且项目快照不变 |
| 已有旧 CLI，显式升级 | 临时 prefix 从 1.14.1 升至 1.14.3；产生新的独立备份 |
| 不兼容 custom profile | 在升级前被拦截，项目快照不变 |
| 最终备份修复后的显式升级 | 再次真实联网刷新，备份保留定制内容，安装结果与固定来源一致 |

隔离日志目录：`/tmp/codex-strategy-integration-yvz5kvt6/`。包含 fresh.log、default-repeat.log、upgrade-skills.log、old-cli-default-rejected.log、upgrade-old-cli.log、incompatible-profile-rejected.log 和 final-upgrade.log；日志属于临时证据，不作为项目运行依赖。

## 用户环境与边界

- 验证前后默认 Node.js 为 22.17.0、OpenSpec 为 1.14.1。
- 用户 `.agents/skills`、OpenSpec 配置目录及现有 `.agents/.skill-lock.json` 的文件哈希/链接快照一致。
- 未在当前仓库运行初始化器，未安装项目技能或生成占位开发文档。
- npm 故障、备份失败、技能中断及更高版本保留采用故障注入/模拟验证；真实联网覆盖上述 7 个脚本场景，不宣称已验证所有未来版本。
- 未提交、推送或归档；change 可进入 review。

## Review 复验

基线为 `b54a5bd`，审查范围包含其后的未提交实现和本 change。Standards 与 Spec 两条独立审查线确认同一个 Major：Skills CLI 1.7.4 普通输出模式在逐技能失败或部分请求名称不存在时可能退出 0，最终文件存在检查会被旧文件误导。

真实固定版 CLI 的本地来源测试已复现两类情况：普通模式退出 0，JSON 模式退出 1。修复为添加 `--json`，并增加“刷新失败但旧文件仍在”和“来源只匹配部分技能”的回归测试；前者在修复前失败、修复后通过。

原始复现日志：`/tmp/skills-exit-review-_iajde2z/` 和 `/tmp/skills-selection-review-yd4hqorb/`。复审与最终验证结果见 review.md。
