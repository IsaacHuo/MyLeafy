# MyLeafy 交付与发布

主线通过检查后只准备测试环境与私有 Android 候选。正式发布入口各自独立：Android 在 admin，iOS 在 App Store Connect，Cloudflare 在 GitHub Actions。两端版本号独立。

## 工作流与首次配置

| 工作流 | 触发/结果 | 人工决定 |
|---|---|---|
| CI | 任务分支、PR、main；按跨目录依赖检查，汇总 CI result | 通过当前提交后合入 main |
| Prepare Android candidate | main CI 成功；仅未发行的新 versionCode 准备签名 APK | admin 下载验收 |
| Publish approved Android candidate | admin 保存授权后调用固定工作流；不重新构建 | 超级管理员确认已验收并发布 |
| Prepare Cloudflare staging | main CI 成功且后端/网站有变化；手动运行可强制准备 | 在隔离环境验收 |
| Publish accepted Cloudflare version | 手动指定提交、成功 staging run 并确认验收 | production Environment 等待 IsaacHuo 批准 |
| Recover Cloudflare services | 指定环境和部署报告，确认旧代码兼容当前数据库 | production 仍需批准 |
| Record released iOS version | 手动确认 Apple 已发布，填写提交/版本/build | Apple 的发布决定仍在 App Store Connect |

GitHub Environments 为 `staging`、`production`、`android-candidates`、`android-production`，只允许 main；production 不允许管理员绕过审批，允许本人批准本人发起的部署。Android 的人工审批在 admin，不另加一个重复的 Environment 审批。

首次接通时按顺序完成：

1. 在 staging/production Environment 中分别保存 `CLOUDFLARE_API_TOKEN`；仅授予目标账号需要的 Workers Scripts、D1、R2、Pages 编辑权限。各自设置 `CLOUDFLARE_PAGES_PROJECT`：生产现有项目 `leafy`，测试独立项目如 `myleafy-site-staging`，两者的 production branch 均为 main。
2. 测试 Pages 绑定 `myleafy-api-staging`；生产 Pages 绑定 `myleafy-api-production`。仓库的 `site/wrangler.<environment>.jsonc` 明确 AdminAPI 和 PublicAPI 绑定。官网下载区同样使用自身 PublicAPI 绑定，部署后回读网站/后端发行信息并比较。测试项目 `.pages.dev` 页面显示预览提示。
3. 关闭现有 Pages 项目的生产 Git 自动部署；测试项目也使用受控部署。脚本会在任何迁移和 Worker 写入前检查 Pages 权限与自动部署状态，配置不完整就停止。
4. production Worker Secret `GITHUB_RELEASE_TOKEN` 限定 `IsaacHuo/MyLeafy`，Contents 只读、Actions 读写。它用于读取私有 draft 和运行状态、发起固定发布工作流，永不发送给浏览器。Cloudflare 只能列出 Secret 名称；真实有效性由管理员下载/发布请求验证。不要将其设置为 `VITE_` 变量。
5. 继续使用现有 Android 四个签名 Secrets 与 `MYLEAFY_RELEASE_PUBLISH_TOKEN`。publisher token 仅能登记私有候选；正式上传/登记还必须匹配已保存、已领取的管理员授权。staging/production 的 publisher token 和 R2 bucket 保持独立。
6. 首次 staging 人工确认可写后将 `backend_control` 置为 active。冒烟测试只生成/删除本次随机身份与数据，不改变全局开关、不清理其他验收数据。
7. 通过完整 CI 后才设置 main 的必需检查 `CI result`。完成 staging 验收并由用户批准首次 production 部署后，新版 admin 和发行授权接口才在生产生效。

这些配置中的 Secret 值不进入文档、报告、日志或聊天。工作流存在不代表环境已配置，未部署的功能不能记为生产完成。

## Android：下载验收后发布

1. 在任务分支同时更新 `android/app/build.gradle.kts` 的版本名/code 和 `android-release-notes.md`。code 必须高于全部历史发行，包括已撤回版本。
2. main 的 CI 成功后准备候选。若该 code 已正式发行，本次准备直接跳过；若完整私有候选已存在，重试下载原 APK，核验后继续登记，不覆盖不同内容。上传中断时从原构建的私有 Actions artifact 恢复 APK 与清单（保留 90 天）；原文件不可用或哈希不一致时明确失败，不重新构建替换候选。
3. 登录 admin → Android 版本，查看“待发布”候选的版本、更新说明、来源、检查状态和大小。点击“下载验收”，使用正式候选从当前正式版覆盖升级。`.next` 调试包可并存，但不能代替正式包覆盖升级验收。
4. 超级管理员点击“发布”，核对版本/摘要并勾选已验收。服务端原子保存候选身份、决定人和时间，调用固定 `android-release.yml`。重复点击复用一个进行中授权；网络结果不明时保留“发布中”，不会立即另开任务。
5. Actions 领取匹配自身 run 的授权，读取原 APK，核对正式包名、版本、最低 API、正式证书、大小和 SHA-256；然后上传同一 APK、校验文件、构建信息到 R2 与正式 GitHub Release。文件回读一致后登记 D1，公开 latest/详情/下载返回正式记录。
6. “发布失败”显示可诊断原因，可在 admin 重试。失败授权不会被重新使用；新授权仍指向原候选 APK。若候选被编辑、正式发布或删除，服务端拒绝继续。
7. 撤回立即停止官网和 App 更新推荐，保留历史文件、发行记录和审计。已经安装的问题包用更高 code 修复。

私有候选 API 为 `POST /v1/releases/android/candidates`；授权领取/失败回调为 `/v1/releases/android/operations/:id/{claim,fail}`。这些入口使用 publisher token；正式上传和登记额外要求 `?operation=<已领取授权>`。管理员候选下载由同域 `/api/admin/android-candidate?id=...` 通过私有服务绑定代理，要求有效管理员会话；不返回 GitHub Secret 或私有下载 URL。

状态为待发布、发布中、已发布、发布失败、已撤回。候选与发布授权保存在 D1 0011 的独立表；0010 正式发行数据和公开响应格式保留。进行中授权由后台读取时核对 GitHub 状态，取消/异常退出最终标记失败；尚未确认 dispatch 的请求至少等十分钟后再判定是否未启动。

## Cloudflare：验收指定提交

staging 与 production 的部署按环境分别串行，恢复使用同一串行锁。相关 main 提交检查通过后，staging 依次执行：Pages 权限预检、记录旧部署 ID 与 D1 恢复书签、迁移、Worker、隔离社区冒烟、网站、公开核对。提交对比从当前 staging 的 `/health.commit` 开始，避免遗漏此前未部署的提交。

验收完毕，在 Actions 运行 **Publish accepted Cloudflare version**：

- `commit`：staging 报告中完整 40 位提交。
- `staging_run`：成功 staging 运行 ID。
- `accepted`：确认已完成验收。

production 等待用户批准。工作流读取该运行的部署报告，核对环境、提交与成功状态；checkout 同一提交，使用锁定依赖构建。迁移、Worker、网站依次进行，失败即停止。发布报告包含源码、旧/新 Worker version、Pages deployment、D1 书签和核对结果。`/health` 与网站 `/release.json` 显示部署提交；后者禁止缓存。

报告中的 D1 书签标记恢复时间点，报告访问遵循仓库权限，不能复制到公开产品页面。客户端契约检查继续覆盖仓库内正式协议及 fixtures；发布人仍需确认在用旧客户端的契约兼容性。新字段优先做可选增量，不提前移除仍在用的接口。

## 发布前短清单

- 客户端：首次启动、免登录、登录/重新认证、关键教务查询、失败保留缓存。真实教务会话由人工验收。
- Android：原正式版覆盖升级保留身份/本地数据，来源授权、取消/继续安装、实际安装版本正确，损坏 APK 被拒绝。
- admin：未登录/非超级管理员不能发布；私有候选不可匿名下载；重复点击、失败重试、撤回后官方入口状态正确。
- 后端/网站：测试与生产绑定正确，未登录管理请求拒绝，社区基本流程与 Android 下载正常。
- 数据库：从当前结构增量迁移，保留用户和已发布/撤回记录，外键检查通过。

## 恢复与 staging 演练

代码恢复与数据库恢复分别决定。[Worker 回滚](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/) 不能恢复 D1 数据；[D1 Time Travel](https://developers.cloudflare.com/d1/reference/time-travel/) 单独处理数据库。

代码恢复：在 **Recover Cloudflare services** 选择 staging/production，填写出现问题那次部署的 run ID、该报告的 commit，并确认旧代码兼容当前数据库。工作流核对来源和两个恢复 ID，恢复部署报告中记录的前一版 Worker 和 Pages，核对部署身份、健康与匿名管理拒绝。报告必须同时含有可恢复的旧 Worker/Pages ID；首次空 Pages 项目没有旧网站可恢复，流程会明确拒绝。

数据库恢复：停止受影响写入、确认书签对应的数据损失范围，由负责人另行决定是否运行 `wrangler d1 time-travel restore myleafy-<env> --env <env> --bookmark <书签>`。代码恢复工作流不执行此命令。恢复后复核用户/发行记录、身份关联和外键，再恢复写入。

staging 演练顺序：确认人工数据基线 → 部署已验收 A → 部署兼容的 B，保留报告 → 用 B 的报告恢复到 A → 核对 Worker/网站 ID、健康、管理拒绝及人工数据仍在 → 再准备当前提交。首次接通未执行演练时，状态文档明确记为待验收。

App 无法靠服务端回滚降级。Android 发布更高 code 修复，iOS 在 Apple 流程中提交修复构建。

## iOS：Apple 发布后记录源码

发布前核对主 App、Widget 和 Share Extension 的 version/build，Xcode 归档和上传对应的已验证提交。TestFlight、送审和正式发布仍在 App Store Connect。普通更新可采用 [Apple 分阶段发布](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/)，紧急修复可全量；分阶段发布不阻止用户手动下载。

Apple 正式发布后运行 **Record released iOS version**。它核对 CI、main 来源和三个目标的版本，创建不可变 annotated `v<version>` tag 和源码记录 Release，不构建/上传未签名归档。重试仅接受同一提交/build 的已有记录，不移动正式 tag。在 `release-notes.md` 记录实际 Apple 构建和用户可见摘要。
