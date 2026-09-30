# Android 认证与版本发布

## 认证恢复

学校会话优先，只有明确失效才恢复。`SchoolCaptchaChallenge` 将登录 key、验证码和匿名 Cookie 固定在同一挑战；验证学校身份成功后才提交新 Cookie。当前身份的 Keystore 凭据用于预填，旧记录可可靠解码才迁移 JSON，无法解码转人工，不清本地业务数据。

Android 不使用离线 OCR 或验证码自动识别，验证码由用户填写。重新认证表单预填与当前学校/门户/账号匹配的加密凭据；验证码刷新和错误不清空账号密码，不会自动提交登录。同一身份的过期请求共享一个验证码挑战；人工认证成功后由原流程恢复查询，不扩大范围。退出或身份变化取消旧任务；Cloudflare 不参与学校认证。

## 发布操作

1. 从 `main` 的已验证 commit 手动运行 **Cut Android Release**，填写与源码一致的版本名。版本 code 必须高于历史正式记录。
2. Actions 执行 JVM、lint 和签名构建，检查包名 `com.myleafy.android`、版本、最低 API 29 及证书。正式签名仍使用原有四个 Android release secrets。
3. `MYLEAFY_RELEASE_PUBLISH_TOKEN` 只用于发行上传/登记，不包含通用 Cloudflare 管理权限。生产和 staging 使用独立 token、R2 bucket 与下载域名。
4. 同一 APK、`.apk.sha256`、`.apk-build-info.txt` 上传 GitHub draft 和 R2；逐个公开回读核验。GitHub Releases 公开与 D1 发布登记都成功、最新 code/hash 一致后才报告发布成功。失败保留不可变文件以重试，不覆盖同版文件。
5. App 和官网均读取 Cloudflare，GitHub 同步归档。版本查询无需账号，不受社区维护状态影响。官网稳定入口：`https://api.myleafy.space/v1/releases/android/download`，校验文件加 `?file=checksum`。

接口：`GET /v1/releases/android/latest?package=com.myleafy.android`、`GET /v1/releases/android/:id`、`GET /v1/releases/android/download`；CI 的 `PUT /v1/releases/artifacts/*` 与 `POST /v1/releases/android/publish` 独立授权。管理员通过现有后台发行列表撤回，保留审计。撤回版本查询返回 410，App 不提示/安装；已安装的问题版通过更高 code 修复。

## 更新安装

“我的 → 检查更新”与前台自动提示使用同一 App 作用域管理器。自动每日一次、稍后延迟同版一天，认证/编辑/操作弹窗期间延后。用户选择下载后 DownloadManager 持续后台任务；恢复进程后继续跟踪，下载完成不绕过应用校验打开 APK。

安装前校验文件大小、SHA-256、包名、版本 code/name、minSdk、签名与当前安装一致，并重新确认发布状态。仅前台引导来源授权并打开系统安装器，取消可继续；实际安装版本达到候选版本后清理。Room v8 不变。

## 验证边界

隔离 staging 已验证上传、公开回读、相同发布重试和撤回；API fixture 不可安装，已撤回。独立模拟器 `emulator-5556` 用于签名正式版本的覆盖安装，用户已登录 `emulator-5554` 不安装、不清数据。生产更新验收记录在 CURRENT 中，尚未执行的网络/权限/设备矩阵不能由代码或单元测试代替。大陆校园网/移动网络尚未测速，不保证 Cloudflare 的大陆下载速度。

## 生产发布与覆盖安装验收（2026-09-30）

生产 1.2.1 / code 5 通过 [正式流水线](https://github.com/IsaacHuo/MyLeafy/actions/runs/36694376242) 发布。Cloudflare 与 [GitHub Releases](https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.2.1) 的包名、版本、commit、大小与 SHA-256 一致；APK 为 53,925,529 字节，SHA-256 为 `fffa642e0765db4feba8f8d611f040e1332bbd50eec081f782a2e962788b814c`，沿用正式签名证书。移除 OCR 后安装包由 1.2.0 的约 95 MB 降为 51.4 MB。

| 验收项 | 实际结果 |
|---|---|
| “我的 → 检查更新” | 1.2.0 手动检查获得 Cloudflare 1.2.1；下载由 App 发起 |
| 实际下载文件 | 模拟器下载的文件大小、SHA-256 与两个发行源一致，App 包身份及签名校验通过 |
| 进程恢复 | 下载完成后强制停止，再启动恢复“已下载并通过校验”；未覆盖下载中的进程退出 |
| 来源授权拒绝 | 就地显示错误，已校验文件保留，可继续安装 |
| 来源授权返回 | 授权后进入系统安装器，无重复下载 |
| 取消安装 | 系统仍为 1.2.0 / code 4；“继续安装”再次打开安装器 |
| 覆盖安装 | 使用系统安装器完成，系统包信息确认 1.2.1 / code 5；未使用 adb 安装候选版本 |
| 数据与清理 | 免登录身份、测试随记和日程保留；确认已安装 code 5 后清理下载任务及文件 |
| 升级后检查 | 页面显示“当前版本 1.2.1”及“已是最新版本” |

本轮截图与详细测试记录仅保留当前评审批次 `android/app/build/emulator-update-latest/`，6 张已逐张审阅。真实学校账号覆盖安装、真实过期会话预填、下载中断续传、空间不足、文件损坏及大陆网络耗时仍需独立现场验收；宿主机基线下载曾中断，Range 恢复后校验通过，不能据此声称大陆分发稳定。

本地手动认证回归、常规 JVM、构建、lint 与显式 `-Pscreenshot` 截图回归通过；发行 commit 的 Android、iOS、backend、site 与仓库安全 CI 均通过。官网/后台既有 Pages Git 自动部署已生效，公开 index/admin bundle 与本地构建 hash 一致，未登录管理 action 返回 401；无需补充 Pages token。Gradle 验证工作流已结束，仅清理 wrapper 自己的临时日志。
