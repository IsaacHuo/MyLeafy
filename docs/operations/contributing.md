# 贡献规范

这个项目的协作流程保持轻量：先开 Issue 说明问题或需求，再从 `main` 拉分支，提交 PR，等 GitHub Actions 通过后合并。

## 分支命名

建议从 `main` 拉新分支并使用小写短横线或数字；这是协作约定，不是 CI 阻断条件：

- `feature/<short-slug>`：新功能
- `fix/<short-slug>`：缺陷修复
- `docs/<short-slug>`：文档变更
- `chore/<short-slug>`：配置、依赖、脚本维护
- `refactor/<short-slug>`：不改变行为的重构
- `test/<short-slug>`：测试补充
- `release/<version>`：发布准备
- `codex/<short-slug>`：Codex 生成或整理的工作分支

示例：`feature/timetable-export`、`fix/admin-login-state`、`docs/supabase-setup`。

## Issue 规范

Bug 使用 Bug report 模板，至少写清楚复现步骤、期望行为、实际行为和环境。功能建议使用 Feature request 模板，说明要解决的问题、最小可用方案和影响范围。

不要在 Issue 里粘贴密码、token、cookie、真实学生个人信息或生产数据库内容。需要说明配置时，只写环境变量名或占位值。

## PR 规范

PR 应该保持小而清晰，标题用一句话说明结果，例如 `Add timetable widget refresh tests`。正文按模板填写 Summary、Linked Issue、Changes 和 Validation。

合并前至少满足：

- PR 关联了对应 Issue，纯文档或很小的维护变更可以例外。
- 本地跑过相关构建或测试；UI 改动看过模拟器、截图或浏览器效果。
- 没有提交 `.env`、本地 xcconfig、证书、profile、服务账号 JSON、Xcode 用户状态或临时脚本。
- 行为、配置或部署方式变化时，同步更新 `docs/`。

## GitHub Actions

PR 和推送到 `main` 会按改动范围触发 CI：

- Repository safety：所有改动都检查不应跟踪的私有文件和明显密钥格式。
- Site CI：仅 `site/**` 变化时运行单元测试和生产构建；`npm run build` 已包含 TypeScript 检查。
- Supabase CI：仅 `supabase/**` 变化时检查和测试 Edge Functions，并从零应用 migration 后运行数据库测试。
- iOS CI：仅 App、扩展、测试、配置或 Xcode 工程变化时执行 iOS 17 build-only 检查。

同一分支连续推送时只保留最新运行。Playwright 双浏览器 E2E、完整 iOS 测试、真机验证和发布检查不属于每次提交的日常门槛，应在重大交互改动或发布前按相关文档执行。

常用发布前命令：

```bash
npm --prefix site run test:e2e
bash scripts/test-ios17-compatibility.sh
```
