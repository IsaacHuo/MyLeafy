# 贡献规范

日常流程：**说明任务 → 从 main 建短期分支 → 本地验证 → 推送并等待 CI result → 快进合入 main → 验收 → 手动发布**。

任务至少说明问题、验收标准和影响范围。小改动在聊天中说明即可；较大功能或架构决策写入 `docs/`。Issue 和 PR 可选，较大改动建议用 PR 展示结果，不要求第二个人批准。

## 分支与合并

1. 确认工作区干净，fetch origin，将 main 快进到 origin/main，核对两者一致。
2. 从这个提交创建 `codex/<task>` 短期分支，不在 main 写任务代码。
3. 运行与风险相称的本地检查，推送分支。**当前提交的 CI result 通过后才合入 main**；失败或取消不能算通过。
4. 快进合入 main，推送并核对本地/远程 main 一致，完成后删除本任务分支。

工作区有未提交改动、main 分叉或无法快进时，保留现场并请求明确解决，不 reset、覆盖或强推。详细规则以 [AGENTS.md](AGENTS.md) 为准。

## 验证与文档

`CI result` 汇总按依赖选择的各端检查。任务分支检查相对 main 的累计改动；PR 检查相对目标分支；main 检查本次提交范围。后台和 admin 契约、共享 fixtures、工作流修改会触发相关端检查。手动运行 CI 检查全部范围。

| 范围 | 日常自动验证 |
|---|---|
| 仓库 | 私有文件/密钥、分层边界、范围选择规则 |
| iOS | Xcode 26.6、iOS 17 最低目标构建、离线 XCTest；中文测试环境，英文行为由显式语言用例验证 |
| Android | JDK 17、受版本控制的 Gradle、构建、JVM、lint、截图差异 |
| 后端 | 锁定 Node 与 npm 依赖、类型/客户端契约、业务/迁移/发行脚本、Worker dry-run |
| 官网/admin | 类型、单元、生产构建、Chromium/WebKit/iPad WebKit 关键浏览器流程 |
| 旧 Supabase | Deno 类型/业务契约、本地数据库迁移与权限测试 |

自动化使用合成数据和离线样本，不依赖真实学校账号、验证码或校园网络。失败时在 Actions 下载 XCTest、浏览器或 Android 诊断产物。真实学校会话与手机覆盖升级按发布清单人工验收。

不提交 `.env`、本地配置、签名材料、token、cookie、学生个人信息或管理员凭据。设计及理由写 `docs/`，已实现结构与状态写 `state/`，可复用根因写 `logs/`，普通历史留给 Git。

## 发布

Android 版本名与 versionCode 更新后，经过 main CI 的正式签名 APK 进入私有 draft 候选。超级管理员在 **admin → Android 版本** 下载验收并决定发布；发布复用同一 APK。不要从 Actions 绕过验收公开新包。

iOS 在 Xcode 归档和上传，在 App Store Connect 使用 TestFlight、送审和发布。Apple 正式发布后，运行 **Record released iOS version**，记录对应提交、版本和 build。主 App、Widget 和 Share Extension 版本必须一致；GitHub Release 只记录源码，不生成未签名安装包。

Cloudflare 合入主线后准备 staging；验收通过后运行 **Publish accepted Cloudflare version**，指定提交和 staging 运行，等待 production 人工批准。数据库迁移、Worker、网站依次进行，前一步失败停止后续步骤。Pages 自动生产部署必须先关闭。

正式 tag 和安装包路径不可覆盖。撤回 Android 仅停止推荐，已安装版本通过更高 versionCode 修复；Worker/网站恢复和 D1 数据恢复分别处理。

配置、验收、失败重试及恢复操作见 [交付与发布手册](docs/operations/delivery.md)。
