# AGENTS.md

MyLeafy 是 iOS、Android、Cloudflare 后端与官网/运营后台共用的 Monorepo。两端共享业务语义与协议，保留平台交互差异，独立验证和发版。

## 仓库知识与任务入口

按顺序阅读本文件、[CURRENT](state/CURRENT.md)、[ARCHITECTURE](state/ARCHITECTURE.md)，跨端任务再读 [PLATFORMS](state/PLATFORMS.md)，然后查看相关设计、排查记录和实际代码。

| 来源 | 唯一职责 |
|---|---|
| `docs/` | 设计、规划、决策理由；`operations/` 保存发布流程与发行证据 |
| `state/` | 当前真实状态、代码结构、跨端能力与验证边界 |
| `logs/` | 有长期复用价值的排查、根因与踩坑知识 |
| Git | 普通改动历史，不在 Markdown 重复 commit log |

当前架构及行为约束以 `state/ARCHITECTURE.md` §11 为入口，最终以代码验证。行为约束变化必须同次更新；架构、模块边界或主要功能状态变化同步更新 CURRENT / ARCHITECTURE，跨端能力或验证/交付状态变化更新 PLATFORMS。未来设计不要写成已实现。

开始任务先明确问题、验收标准、涉及平台、共享契约和发布边界。先检查既有实现与依赖；明确 Bug、跨端需求和技术债先建或复用 Issue，大任务用 PR 展示累积结果。小文案与局部维护可以只用任务分支和 CI，不强制第二人批准。协作细节见 [CONTRIBUTING](CONTRIBUTING.md)。

## 工程原则

1. **保持简单**：选择满足当前需求的最简单实现，不增加猜测性的配置、抽象或基础设施。
2. **按可用层次迭代**：每一步保持产品可用，不以未完成的大改造替换工作路径。
3. **删除过时内部实现，保护已发行数据与契约**：移除无使用者的旧路径，不保留无意义适配层；已发行客户端的用户数据、持久化格式和仍在使用的 API 必须有必要兼容或明确迁移策略、失败恢复和相应验证。不能用“删除旧兼容”跳过 Room / SwiftData / 云端数据升级。
4. **职责清楚**：界面负责呈现与交互，网络、解析、持久化各归所属层；只在职责需要时增加模块，不强制所有页面套同一架构。
5. **先复用现有依赖**：先查文档、API 和类型，确认能力后再写自定义实现。
6. **优先成熟工具**：新增依赖必须减少总体复杂度，并检查兼容与维护成本。
7. **保持长期可维护**：不引入明确准备以后推翻的临时结构，不积累已知结构债。
8. **先研究成熟方案**：沿用已验证的交互、术语和工程惯例；创新应有具体产品原因。
9. **失败可见、修复根因**：不吞错、不用回退掩盖故障；关键信息不足时补诊断。日志默认脱敏，不包含凭据和学生私人内容。

## 平台与代码边界

| 范围 | 技术与导航 |
|---|---|
| iOS | SwiftUI / SwiftData / URLSession / SPM，最低 iOS 17；iOS 26+ 按可用性采用 Liquid Glass；先检查现有 SwiftUI 模式 |
| Android | Kotlin / Compose / Room / DataStore / OkHttp，最低 API 29；保留 features / core 分层及原生交互 |
| Backend | Cloudflare Workers / D1 / R2 / Durable Objects / Better Auth；共享契约在 contracts；旧 Supabase 仍服务已安装旧客户端 |
| 官网/admin | React / TypeScript / Tailwind / Radix / TanStack Query、Table / React Hook Form；管理授权在服务端 |

校园能力决定入口；学校数据、MyLeafy 服务端数据与用户本地数据不得混淆权威来源。共享协议或 fixtures 改动必须检查所有受影响端，不根据开发进度差异降低契约验证要求。

平台差异分成需要对齐、平台特有、刻意保留或待产品决定。iOS 与 Android 的根导航已于 2026-10-23 对齐为「课表 / 校园 / 我的」，社区与日迹作为校园内入口；CloudKit 不代表跨平台云同步承诺。不得为追求版本号或功能数量一致而阻塞另一端独立交付。

## 格式化与验证

固定规则与命令见 [代码规范](docs/engineering/code-style.md)。只处理任务所属文件，保护其他未提交改动；全量格式化必须独立于功能修改提交。

| 范围 | 修改后运行 |
|---|---|
| Swift | `bash scripts/format-swift.sh <任务文件...>`，随后同参数加 `--check`；完整检查省略路径，覆盖 App、测试及扩展 |
| Kotlin / Gradle | `cd android && ./gradlew spotlessApply spotlessCheck`；存在无关编辑时用文档中的绝对路径筛选方式，只处理任务文件 |
| CI 选择规则 | `python3 -m unittest discover -s scripts -p 'test_ci_*.py'` |
| Backend | backend 内 `npm ci`、`npm run typecheck`、`npm run check:contracts`、`npm test` |
| 官网/admin | site 内 `npm ci`、`npm run typecheck`、`npm test`；交互改动验证相关 Playwright 流程 |

- 本地运行与风险相称的构建和测试，遵守用户对当前任务的验证限制。iOS 构建使用任务专用 DerivedData，避免并行 Xcode 构建，关闭索引存储。
- 日常 CI 只做受影响平台的格式、配置、类型/契约与基础安全检查；完整编译/回归由 Full validation 手动按平台运行，快速 CI 通过不代表完整验证。CI 不改写源码；SwiftFormat、Spotless、ktlint 均固定版本，本地与 CI 走同一入口。不通过放宽规则或重录截图掩盖失败。
- 分开报告静态检查、构建、自动化测试、Simulator、真机和真实学校会话；测试代码存在不代表执行通过，CI 通过不代表产品已发布。
- 自动测试使用离线样本和隔离服务，不使用真实学生凭据或改写生产数据。

## Git 与 worktree

1. fetch origin，在安全 checkout 切到 main 并只用 fast-forward 更新到 origin/main，核对一致后创建 `codex/<task>` 专用分支。不得直接在 main 实施。
2. 脏工作区不阻止新任务。先检查所有权和范围；使用独立 worktree 隔离并发工作。不要自动 stash、丢弃、覆盖或暂存无关改动。
3. 只提交任务所属 diff。碰到同文件已有改动时保留并分离；只有无法安全判断所有权、会覆盖工作、冲突无法解决、main 分叉或无法快进时才请求明确解决。
4. 本地验证后推送任务分支，等待其**精确当前提交**的 `CI result` 通过；失败或取消不能被其他提交的成功替代。
5. 主线前进时先更新任务分支，再验证更新后的累积改动。CI 通过后快进集成 main，推送并核对本地、tracking 和远程 main 一致。不得 reset 或强推 main。
6. 删除本任务创建的本地及同名远程分支，不删除其他人的分支。保留需要检查的 worktree，并按任务约定切回 main。

## 完成、验收与发布

Issue 的 Done 表示该 Issue 定义的验收条件已满足；代码合入后仍待产品验收时进入 Acceptance。跨端总 Issue 只能在各子项满足约定条件后关闭，单端先完成不能关闭整个需求。合入、自动化通过、真机验收、正式发布是独立事实。

- Android：main 基础 CI 通过后手动准备私有正式签名候选；超级管理员在 Android 版本页下载、覆盖升级验收后授权正式发布，复用同一 APK。
- iOS：Xcode Archive → TestFlight / App Store Connect；Apple 正式发布后运行 **Record released iOS version** 记录已发布二进制对应的源码、version/build 和不可变 tag。
- Cloudflare：staging 验收指定提交，production 需要所有者在 GitHub Actions 批准。代码恢复与数据库恢复分别决定。

[交付手册](docs/operations/delivery.md) 是发布操作和短清单入口，[发布索引](docs/operations/release-notes.md) 保存已核实的发行证据。不要推断缺失的源码、build 或真机结果，不移动正式 tag，不把当前源码版本当成已发布版本。
