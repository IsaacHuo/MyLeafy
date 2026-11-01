# MyLeafy 交付与发布

> 2026-11-02：后端、网站与业务域名已迁至阿里云 ECS，生产已通过所有者审批和实际验收。现行部署/恢复见 [ECS 交付](ecs-delivery.md)，旧 Cloudflare 工作流已停用。

主线通过基础检查后不会自动准备环境或候选；手动准备测试环境与私有 Android 候选。正式发布入口各自独立：Android 在 admin，iOS 在 App Store Connect，ECS 在 GitHub Actions。两端版本号独立。

## 工作流与首次配置

| 工作流 | 触发/结果 | 人工决定 |
|---|---|---|
| CI | 仓库分支 push（PR 复用）；只做受影响平台基础静态检查，汇总 CI result | 通过当前提交后合入 main |
| Full validation | 手动选择平台/all，固定事件源码 SHA，完整编译/回归，不发布 | 发布前按相关平台保留完整证据 |
| Prepare Android candidate | main 基础 CI 成功后手动运行；仅未发行的新 versionCode 准备签名 APK | admin 下载验收 |
| Publish approved Android candidate | admin 保存授权后调用固定工作流；不重新构建 | 超级管理员确认已验收并发布 |
| Prepare or publish accepted ECS version | main 精确提交，staging 完整验证；production 消费同一压缩包 | production Environment 等待所有者批准 |
| 旧 Cloudflare 部署/恢复 | 已禁用，仅保留历史源资源 | 清退需另行确认，禁止与 ECS 双写 |
| Record released iOS version | 手动确认 Apple 已发布，填写提交/版本/build | Apple 的发布决定仍在 App Store Connect |

GitHub Environments 为 `staging`、`production`、`android-candidates`、`android-production`，只允许 main；production 不允许管理员绕过审批，允许本人批准本人发起的部署。Android 的人工审批在 admin，不另加一个重复的 Environment 审批。

首次接通时按顺序完成：

1. 安装专用 Node/Caddy、系统用户及隔离目录；staging/production 配置独立数据库、文件、密钥和服务。公开入口启用前完成备案核验。
2. 在两个 Environment 配置仅限目标 ECS 的 Workbench RAM 凭据，不使用初始化全账号 AccessKey。实例变更时同步工作流目标及 RAM 策略。
3. 真实配置仅保存在 `/etc/myleafy/<environment>.env`；备份密钥单独保存。`GITHUB_RELEASE_TOKEN` 仅限本仓库 Contents 读取、Actions 读写，不给浏览器或 `VITE_` 变量。生产 publisher token 与仓库 `MYLEAFY_RELEASE_PUBLISH_TOKEN` 一致。
4. 先执行指定提交的 staging，检查完整测试、部署报告及网站/API 同一源码；production 使用该成功运行保存的同一归档，经过所有者批准后安装。
5. 原有 Android 签名 Secrets 与管理员发布授权继续保留；staging 和 production 的 publisher token、数据与文件独立。冒烟仅生成/删除本轮随机测试身份，不修改全局控制开关或其他验收数据。
6. 启用 systemd 与每日加密备份；首次安装和换机均进行实际下载/恢复校验。完整流程及配置快照见 [ECS 交付](ecs-delivery.md) 和 [Configuration](https://github.com/IsaacHuo/Configuration/tree/main/myleafy-ecs)。

这些配置中的 Secret 值不进入文档、报告、日志或聊天。工作流存在不代表环境已配置，未部署的功能不能记为生产完成。

## Android：下载验收后发布

1. 在任务分支同时更新 `android/app/build.gradle.kts` 的版本名/code 和 `android-release-notes.md`。code 必须高于全部历史发行，包括已撤回版本。
2. main 的基础 CI 成功后，在 Actions 手动运行 Prepare Android candidate；它保留 JVM、release lint 和正式签名构建。若该 code 已正式发行，本次准备直接跳过；若完整私有候选已存在，重试下载原 APK，核验后继续登记，不覆盖不同内容。上传中断时从原构建的私有 Actions artifact 恢复 APK 与清单（保留 90 天）；原文件不可用或哈希不一致时明确失败，不重新构建替换候选。
3. 登录 admin → Android 版本，查看“待发布”候选的版本、更新说明、来源、检查状态和大小。点击“下载验收”，使用正式候选从当前正式版覆盖升级。`.next` 调试包可并存，但不能代替正式包覆盖升级验收。
4. 超级管理员点击“发布”，核对版本/摘要并勾选已验收。服务端原子保存候选身份、决定人和时间，调用固定 `android-release.yml`。重复点击复用一个进行中授权；网络结果不明时保留“发布中”，不会立即另开任务。
5. Actions 领取匹配自身 run 的授权，读取原 APK，核对正式包名、版本、最低 API、正式证书、大小和 SHA-256；然后上传同一 APK、校验文件、构建信息到 ECS 发行目录与正式 GitHub Release。文件回读一致后登记 SQLite，公开 latest/详情/下载返回正式记录。
6. “发布失败”显示可诊断原因，可在 admin 重试。失败授权不会被重新使用；新授权仍指向原候选 APK。若候选被编辑、正式发布或删除，服务端拒绝继续。
7. 撤回立即停止官网和 App 更新推荐，保留历史文件、发行记录和审计。已经安装的问题包用更高 code 修复。

私有候选 API 为 `POST /v1/releases/android/candidates`；授权领取/失败回调为 `/v1/releases/android/operations/:id/{claim,fail}`。这些入口使用 publisher token；正式上传和登记额外要求 `?operation=<已领取授权>`。管理员候选下载由同域 `/api/admin/android-candidate?id=...` 经 Node 同域内部代理，要求有效管理员会话；不返回 GitHub Secret 或私有下载 URL。

状态为待发布、发布中、已发布、发布失败、已撤回。候选与发布授权保存在 SQLite migration 0011 的独立表；0010 正式发行数据和公开响应格式保留。进行中授权由后台读取时核对 GitHub 状态，取消/异常退出最终标记失败；尚未确认 dispatch 的请求至少等十分钟后再判定是否未启动。

## ECS：验收指定提交

在 **Prepare or publish accepted ECS version** 选择 staging 并填写精确源码 SHA。工作流核对 main 来源和该提交 `CI result`，完整验证后端、迁移、网站和浏览器，构建并保存带 SHA-256/逐文件清单的产物，部署到独立测试目录。

验收后选择 production，填写同一 `commit`、成功的 `staging_run` 及 `accepted=true`。所有者在 GitHub production Environment 批准；production 下载 staging 的原归档，不重新构建，核对后安装依赖、备份、停服务、迁移、切换 current 并检查健康。按环境串行，失败不自动回退数据库。

部署报告包含来源提交、上一产物、校验及健康结果，网站 `/release.json` 与 API `/health` 必须一致。Caddy 和 DNS 的初次启用由操作者单独核验。旧 Cloudflare 工作流不能用于当前源码。详细步骤见 [ECS 交付](ecs-delivery.md)。

## 发布前短清单

需要单独回归时，在 Actions 的 Full validation 选择分支及平台（默认 all）；它固定当前事件 SHA，不发布。iOS 在 Archive 前保留同源码的完整验证证据。

按每个平台候选单独执行并记录 version/build（Android code）、精确源码、检查链接、验收人/日期和待处理项。合入 main、CI 成功和候选生成都不代表以下产品验收完成；不适用项注明原因。

- 来源：精确候选源码的基础 CI result 成功，未将失败或取消任务当成通过；相关平台的手动完整验证及候选自身构建测试另行核对，不能以基础 CI 代替。
- iOS：正式签名 Archive / TestFlight 的主 App、Widget、分享扩展 version/build 一致；按本版改动验证 SwiftData 升级、CloudKit 生产环境/双设备、通知、小组件和系统日历；未完成的实际设备结果明确保留。
- 数据升级：从当前正式版覆盖升级，检查身份、课程、个人日程、随记/媒体、备注、提醒和设置。已有数据库与在用 API 契约必须有兼容或可验证迁移，失败可恢复，不能以全新安装成功代替升级验收。
- 追溯：版本/build、精确源码、不可变 tag、发布说明、实际二进制一致；Android 同一 APK 的 SHA-256 / 正式证书核对，iOS 以 Apple 已发布归档/构建证据核对。缺失证据记录待核实，不用当前 main 补猜。

- 客户端：首次启动、免登录、登录/重新认证、关键教务查询、失败保留缓存。真实教务会话由人工验收。
- Android：原正式版覆盖升级保留身份/本地数据，来源授权、取消/继续安装、实际安装版本正确，损坏 APK 被拒绝。
- admin：未登录/非超级管理员不能发布；私有候选不可匿名下载；重复点击、失败重试、撤回后官方入口状态正确。
- 后端/网站：测试与生产绑定正确，未登录管理请求拒绝，社区基本流程与 Android 下载正常。
- 数据库：从当前结构增量迁移，保留用户和已发布/撤回记录，外键检查通过。

## 恢复与 staging 演练

代码恢复和数据库恢复分别决定。ECS 代码恢复仅在旧产物兼容当前数据库时切回，操作前停写并生成备份；不自动恢复旧数据库掩盖迁移错误。数据库恢复使用新目录和匹配密钥，逐表/逐文件检查后再决定何时开放写入，不能覆盖唯一故障现场。

换机和完整灾难恢复参照 [Configuration 恢复手册](https://github.com/IsaacHuo/Configuration/blob/main/myleafy-ecs/RESTORE.md)。当前已经完成源停写、一致导出、Mac/ECS 导入验证、原 APK 核验及生产备份异机恢复；未来新实例需重新核对目标、备案接入和密钥，不能把模板当真实配置。

旧 Cloudflare 的版本、D1 书签与回退记录作为历史源保留。ECS 已接收新写入，不能只恢复旧 Worker/Pages 或切回旧 D1；应先保护新数据，再明确恢复方案。旧恢复工作流已禁用，邮箱与其他项目资源保持独立。

App 无法靠服务端回滚降级。Android 发布更高 code 修复，iOS 在 Apple 流程中提交修复构建。

## iOS：Apple 发布后记录源码

发布前核对主 App、Widget 和 Share Extension 的 version/build，Xcode 归档和上传对应的已验证提交。TestFlight、送审和正式发布仍在 App Store Connect。普通更新可采用 [Apple 分阶段发布](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/)，紧急修复可全量；分阶段发布不阻止用户手动下载。

Apple 正式发布后运行 **Record released iOS version**。它核对 CI、main 来源和三个目标的版本，创建不可变 annotated `v<version>` tag 和源码记录 Release，不构建/上传未签名归档。重试仅接受同一提交/build 的已有记录，不移动正式 tag。在 `release-notes.md` 记录实际 Apple 构建和用户可见摘要。

基础 CI 只由仓库分支 push 触发，PR 直接复用源提交检查；同分支新提交自动取消旧执行，不创建同一提交的重复 pull_request 运行。实测即使最新一轮成功，同提交另一轮 CANCELLED 的必需检查仍会阻塞 GitHub，不能依赖并发组单独消除重复事件。只等待精确当前提交的有效 CI result 实际成功；不要绕过保护或强推 main。旧行为见 logs/required-ci-checks.md。
