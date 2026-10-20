## ADDED Requirements

### Requirement: Fixed installation baseline
初始化器 SHALL 使用脚本集中定义的 OpenSpec 版本、Skills CLI 版本和经验证的 Matt Pocock 完整提交 SHA；安装不得解析浮动 latest/main 作为替代。已确认工具基线为 OpenSpec 1.14.3、Skills CLI 1.7.4，技能 SHA 为 `5beb35b040e3de97e54fa9e386d7e42d15c295c2`。

#### Scenario: Installing missing dependencies
- **WHEN** 所需工具或技能缺失且前置检查通过
- **THEN** 安装命令使用固定目标，输出版本和来源提交

#### Scenario: Fixed source unavailable
- **WHEN** 固定包或提交不可获取，或缺少任一要求的技能
- **THEN** 非零退出并报告失败，不回退到浮动来源

### Requirement: Runtime preflight
初始化器 SHALL 在安装、刷新和项目写入前校验 Node.js >=22.20.0 以及所需命令。参数仅支持默认运行、--upgrade、--help，帮助输出和未知参数不得触发安装；脚本不得自动升级 Node.js。

#### Scenario: Old Node runtime
- **WHEN** Node.js 为 20.19.0、22.17.0 或 22.19.0
- **THEN** 提示最低版本并退出，全局工具和项目内容不变

#### Scenario: Supported runtime
- **WHEN** Node.js 为 22.20.0 或更高版本且所需命令存在
- **THEN** 继续检查配置与安装目标

#### Scenario: Help or unknown argument
- **WHEN** 请求 --help 或传入未知参数
- **THEN** 分别输出帮助并成功退出，或报告参数错误并非零退出，两者均不安装或写入项目

### Requirement: OpenSpec installation modes
初始化器 SHALL 在缺失时安装固定 OpenSpec；默认模式对低于基线的版本提前停止并提示 --upgrade；升级模式将旧版本安装到固定目标；两个模式都复用目标或更高版本且不降级。无法读取或解析版本必须报错。

#### Scenario: Default run with older OpenSpec
- **WHEN** 未使用 --upgrade 且已安装 OpenSpec 低于固定目标
- **THEN** 在安装和项目刷新前停止，显示当前版本及显式升级入口

#### Scenario: Explicit upgrade from older OpenSpec
- **WHEN** 使用 --upgrade、前置检查及备份通过，且 OpenSpec 低于目标
- **THEN** 安装固定目标，核对实际版本后继续

#### Scenario: Same or newer OpenSpec
- **WHEN** 已安装版本等于或高于目标
- **THEN** 不执行全局 npm 安装，报告实际版本并继续配置检查

### Requirement: Configuration protection
初始化器 SHALL 对已可用 OpenSpec 在修改前检查 delivery，并对已有项目检查 profile/workflows，保留现有拒绝条件。安装或升级后必须再次检查配置才可刷新项目；不得自动修改全局配置。

#### Scenario: Incompatible custom workflows
- **WHEN** 已有项目的 custom 缺少 propose、apply 或 archive
- **THEN** 在全局升级、技能替换或项目刷新前非零退出，保留现有项目内容

#### Scenario: Configuration cannot be read
- **WHEN** 已安装 CLI 无法读取所需配置
- **THEN** 输出实际失败及独立处理指引，不以升级或重置配置绕过检查

#### Scenario: Failure after global installation
- **WHEN** OpenSpec 已安装成功但后续配置复查失败
- **THEN** 停止项目操作并说明全局安装已发生，不宣称已回滚

### Requirement: Managed project skill scope
初始化器 SHALL 仅管理原有 9 个 Matt Pocock 技能，继续在当前项目使用 Codex copy 模式。默认模式仅补齐缺失路径并保留已有路径；--upgrade 才可刷新已有普通技能目录。不得安装插件或更新用户级及其他来源技能。

#### Scenario: Default run preserves customizations
- **WHEN** tdd/SKILL.md 已有项目定制内容
- **THEN** 默认运行后该内容不变，其余缺失的受管理技能按固定来源安装

#### Scenario: Explicit scoped refresh
- **WHEN** --upgrade 且备份成功
- **THEN** 仅选中原有 9 个技能刷新或补齐，不相关技能内容不变

### Requirement: Backup before upgrade mutations
初始化器 SHALL 在显式升级的全局安装、项目刷新及技能替换前，将受管理技能原目录、已有 skills-lock.json 和恢复清单备份到 .init-codex-backups 下独占创建的运行目录。清单必须记录原先缺失项及安装目标；备份不得位于技能发现目录，必须保留并输出路径。

#### Scenario: Repeated upgrades
- **WHEN** 连续运行两次 --upgrade
- **THEN** 每次使用不同备份目录，不覆盖前一次备份

#### Scenario: Backup failure
- **WHEN** 任一需要备份的内容无法复制
- **THEN** 非零退出，不执行全局安装、项目刷新或技能替换

#### Scenario: Unsafe upgrade path
- **WHEN** 技能目标或父目录、锁文件、备份父路径存在不支持的符号链接或文件类型
- **THEN** 升级在修改前停止，保留原路径，不跟随链接写入外部位置

### Requirement: Honest failure and readiness reporting
初始化器 SHALL 输出执行模式、工具版本、技能来源、操作清单和备份位置。安装失败必须非零退出并说明阶段及可能已发生的变化，提供人工恢复指引；成功才运行现有 readiness 判断，不宣称升级具有跨全局工具和项目的事务回滚。

#### Scenario: Interrupted skill installation
- **WHEN** 备份成功后技能安装中途失败
- **THEN** 保留备份，报告可能部分更新及恢复方法，不输出 READY 或自动删除恢复依据

#### Scenario: Successful initialization with placeholders
- **WHEN** 安装与验证成功但文档仍包含占位标记
- **THEN** 显示 INITIALIZED, NOT READY FOR DEVELOPMENT，沿用现有文档填写流程

#### Scenario: Failed refresh leaves old files present
- **WHEN** 安装器无法替换某个技能，但其旧 SKILL.md 仍存在
- **THEN** 初始化器仍非零退出并报告安装失败，不以旧文件存在作为升级成功的依据

#### Scenario: Only some requested skills exist in the source
- **WHEN** 来源中只有部分请求技能可匹配
- **THEN** 初始化器非零退出，即使其他技能已安装、未匹配技能的旧文件仍存在，也不输出成功状态

### Requirement: Preserve foreign source ownership
初始化器 SHALL 在显式升级预检时检查已有项目技能锁文件；若所选名称被明确记录为其他来源，必须停止，不能将同名技能当作 Matt Pocock 技能覆盖。无法读取或解析已有锁文件时同样停止；缺少锁文件的旧技能可在备份后升级。

#### Scenario: Selected skill belongs to another source
- **WHEN** skills-lock.json 将 tdd 记录为其他仓库的技能
- **THEN** 在备份及升级写入前报告来源冲突并退出，保留原技能及锁文件
