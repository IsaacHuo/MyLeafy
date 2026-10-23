# 贡献规范

MyLeafy 使用一个 Monorepo、`main + codex/*` 短期分支和统一 `CI result`；iOS、Android 独立实现、验证和发版。工程与数据保护原则见 [AGENTS.md](AGENTS.md)。

## 任务、Issue 与 PR

任务先说明问题、涉及平台、共享契约、验收条件和发布边界。先查现有 [Issues](https://github.com/IsaacHuo/MyLeafy/issues) 及关联事项，避免重复创建。

- 明确 Bug、跨端需求与技术债先建或复用 Issue。小文案和局部维护可以直接走任务分支及 CI。
- 大任务使用 PR，说明具体问题、结果与真实验证；不强制第二个人批准，不要求每个 commit 创建 Issue。
- 跨端复杂需求使用总 Issue 与平台子 Issue，各自关联 PR 和验收条件。一个平台可以先完成和发布；总 Issue 不因单端合入自动关闭。
- 标签仅使用必要维度：平台 `ios/android/backend/admin`，工作类型沿用 `bug/enhancement/documentation` 并补 `maintenance`，优先级 `P0/P1/P2`。P0 表示严重安全、数据损失或核心功能不可用，P1 为近期重要工作，P2 为常规改进。
- 单一 [MyLeafy Development](https://github.com/users/IsaacHuo/projects/1) Projects 看板关联本仓库。状态为 Backlog（待评估）、Ready（验收明确）、In Progress、Acceptance（待验收）、Done（Issue 验收满足）。发布状态以发行证据单独记录，不能从看板列推断。

## 分支与工作区

1. fetch origin，在安全 checkout 切到 main，只用快进更新并核对与 origin/main 一致，再创建 `codex/<task>`。
2. 存在无关未提交改动时检查所有权并保留，安全时使用独立 worktree 继续。不要自动 stash、reset、覆盖或混入其他人的 diff。
3. 完成风险相称的本地验证，推送分支并等待当前提交的 `CI result` 通过。失败、取消或其他提交的成功都不能算当前提交通过。
4. 主线前进时先更新任务分支并重新验证当前提交，再快进集成 main，推送并核对本地/远程一致；完成后删除本任务分支。

只有继续会丢失或覆盖工作、所有权不明、冲突无法安全解决、main 分叉或无法快进时才暂停请求解决。不得强推 main 绕过门禁。

## 代码风格与验证

[代码规范与工具](docs/engineering/code-style.md) 定义固定版本、范围及命令。Swift 用 `bash scripts/format-swift.sh [任务路径...]`，Android 在 android 内运行 `./gradlew spotlessApply spotlessCheck`。不要格式化他人的未提交工作；纯格式化和功能修改分开提交。

CI 只检查源码；风格检查失败时按同一工具修复。范围选择覆盖相关跨目录依赖：共享 contracts 触发相关客户端和后端；Swift 主 App 变化仍触发后端契约扫描；工作流修改验证全部范围。手动 CI 检查全部范围。

| 范围 | 自动验证 |
|---|---|
| 仓库 | 私有文件/密钥、分层边界、CI 范围选择规则 |
| iOS | 固定 SwiftFormat；Xcode 26.6、iOS 17 最低目标构建、离线 XCTest；中文环境与显式英文用例 |
| Android | 固定 Spotless / ktlint；现有 Gradle/JVM toolchain、Debug 构建、JVM、Android Lint、Roborazzi |
| Backend | 锁定 Node/npm 依赖、类型、客户端契约、业务/迁移/发行脚本、Worker dry-run |
| 官网/admin | 类型、单元、生产构建、Chromium/WebKit/iPad WebKit 浏览器流程 |
| 旧 Supabase | Deno 类型/业务契约、本地数据库迁移和权限 |

测试代码存在、测试编译成功、测试执行通过要分别表述；本地、CI、Simulator、真机和真实学校会话各自标明。自动测试使用合成数据和离线样本，不依赖学生账号、验证码或校园网。真机覆盖升级和产品交互按发布清单人工验收。

## 文档与跨端状态

- 设计与理由进入 docs，现状进入 state，可复用排查进入 logs，普通历史保留在 Git。
- [PLATFORMS](state/PLATFORMS.md) 是主要功能的跨端实现、验证和交付差异入口；[ARCHITECTURE](state/ARCHITECTURE.md) 保存当前结构和行为约束。
- 主要功能状态或架构变化同次更新 state；跨端事项只更新受影响的平台与证据，不覆盖另一端独立结果。
- 平台差异明确归类：需要对齐、平台特有、刻意保留或待产品决定。版本号独立，不强制同步发版。
- 已发行用户数据、持久化格式和在用 API 需要必要兼容或明确迁移和恢复；不能按内部代码清理方式直接删除。
- 不提交本地配置、签名材料、token、Cookie、学生个人信息或管理员凭据。

## 发布与追溯

[交付手册](docs/operations/delivery.md) 集中维护发布步骤与验收短清单，[发布索引](docs/operations/release-notes.md) 记录版本/build、源码、tag、产物或商店证据及验收边界，GitHub Release 保存对外说明和产物。

Android 继续使用私有候选与管理员授权，发布同一 APK；iOS 继续使用 Xcode / App Store Connect，Apple 发布后再记录源码；Cloudflare 生产部署仍需所有者批准。CI 通过、合入 main 或更新源码版本都不会自动代表正式发布。
