# MyLeafy 文档中心

本目录是 MyLeafy 的**设计与规划**文档入口：产品思路、设计、技术方案、规划与决策 rationale。它回答“我们要建什么、为什么这样设计”，与描述现状的文档分开：

```text
docs/   → What we intend to build, and why.   （本目录：设计与规划）
state/  → What exists now.                    （../state/，当前真实状态）
logs/   → What we learned while debugging.    （../logs/，可复用排查知识）
git     → What changed.                       （普通改动历史）
```

- **当前代码结构与分层**：见 [`state/ARCHITECTURE.md`](../state/ARCHITECTURE.md)。
- **当前开发进度与重点**：见 [`state/CURRENT.md`](../state/CURRENT.md)。
- **可复用的调试与根因知识**：见 [`logs/`](../logs/)。

## 推荐阅读

1. [项目总览](product/overview.md)：产品定位、能力范围、数据来源与当前限制。
2. [App 产品设计](design/app-design.md)：信息架构、核心流程、页面职责与状态约定。
3. [当前架构](../state/ARCHITECTURE.md)：当前代码结构、分层、数据流与行为约束。
4. [Supabase 接入](engineering/supabase.md)：身份、数据域、RLS、Storage、Functions 与本地环境。
5. [贡献规范](../CONTRIBUTING.md)：日常开发、验证和协作方式。

## Product

| 文档 | 内容 |
|---|---|
| [项目总览](product/overview.md) | 项目定位、系统组成、能力、所有权和发展方向 |
| [App 功能总结](product/app-features.md) | 当前 iOS App 与小组件的功能清单；含课表学年范围和日迹入口 |
| [发展方向](product/roadmap.md) | 非承诺式工程和产品优先级 |
| [未来功能展望](product/future-features.md) | 用户侧候选能力、边界与验证标准 |

## Design

| 文档 | 内容 |
|---|---|
| [App 产品设计](design/app-design.md) | 产品目标、五项根导航、日迹入口、核心页面和全局状态 |
| [UI 风格规范](design/ui-style-guide.md) | 主题、字体、间距、白色日迹卡片、Tag 胶囊、评分星级、组件、动效和可访问性 |
| [UI 实现总结](design/ui-implementation.md) | 当前 iOS 页面与组件的设计实现 |

## Engineering

| 文档 | 内容 |
|---|---|
| [Supabase 接入](engineering/supabase.md) | Auth、Database、RLS、Storage、Functions 和联调 |
| [运营后台](engineering/admin-console.md) | Web 后台、RBAC、代理、安全、开发和测试 |
| [后台可靠性](engineering/admin-backend-reliability.md) | 管理动作、错误契约和发布顺序 |

当前代码分层、数据流与行为约束以 [`state/ARCHITECTURE.md`](../state/ARCHITECTURE.md) 为权威；本文档中的 Engineering 文档按各自主题补充设计细节和 rationale。

数据库迁移顺序和关键不变量由代码旁的 [`supabase/schema-ledger.md`](../supabase/schema-ledger.md) 维护；网站开发说明位于 [`site/README.md`](../site/README.md)。

## Operations

| 文档 | 内容 |
|---|---|
| [贡献规范](../CONTRIBUTING.md) | 分支、PR、日常 CI 和发布前验证 |
| [发布记录](operations/release-notes.md) | 正式版本、Git tag、发布源码和用户可见更新摘要 |
| [App Store 记录](operations/app-store/) | 特定版本的审核、元数据和重新提交记录 |

`operations/` 中的日期或版本文档是历史记录，不代表当前产品行为。可复用的故障排查与根因复盘已迁移到 [`logs/`](../logs/)；审核复盘中的调试知识仍可查阅 [`operations/app-store/2.9-build-22-review.md`](operations/app-store/2.9-build-22-review.md)。

## 维护规则

- 文档默认使用中文，代码标识、命令和协议名保留原文。
- **职责边界**：本文档记录设计与规划（What we intend）；当前实现与进度进入 [`state/`](../state/)，排查知识进入 [`logs/`](../logs/)。不要把现状和设计混写在同一文档。
- 当前产品事实进入 Product、Design 或 Engineering；发布记录和复盘进入 Operations。
- Product、Design 和 Engineering 默认描述当前 `main`，不嵌入容易过期的版本/build 限定；正式版本、tag 和源码提交统一记录在发布记录中。
- 不建立通用历史归档目录。仍有明确复用价值的历史材料放入具体运维分类，无维护价值的临时计划和操作记录直接删除。
- 链接使用仓库相对路径，不写本机绝对路径。
- 用户可见能力必须注明数据来源、可用条件和失败边界。
- 不提交生产密钥、Cookie、密码、真实学生数据、管理员凭据和内部发布权限。
- 代码行为、数据库 schema、管理 action 或 UI token 变化时，在同一变更中更新对应文档；架构、模块边界或主要功能状态变化时，同时更新 `state/ARCHITECTURE.md` 与 `state/CURRENT.md`。
- Mermaid 图表直接嵌入对应 Markdown，由 GitHub 原生渲染；复杂图应拆分并检查浅色、深色和移动端可读性。
