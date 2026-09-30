# Android 认证与版本发布

## 认证恢复

学校会话优先，只有明确失效才恢复。`SchoolCaptchaChallenge` 将登录 key、验证码和匿名 Cookie 固定在同一挑战；验证学校身份成功后才提交新 Cookie。当前身份的 Keystore 凭据用于预填，旧记录可可靠解码才迁移 JSON，无法解码转人工，不清本地业务数据。

ML Kit Latin 模型随 APK 打包；原图、4 倍图、灰度增强图在设备上处理，至少两路四位字母数字一致且支持结果置信度均 ≥0.85 才采纳。最多三张，间隔 300ms。首次登录只填入，自动恢复才提交；密码错误、未知错误和网络错误停止。6 张实际匿名学校验证码样本均低于门槛，自动恢复的真实识别覆盖率目前是 0/6，不能视为学校登录实测通过。模型没有图片上传，但 ML Kit SDK 的诊断采集需在隐私说明中披露。

同一身份的并发请求共用恢复；认证后原请求最多重试一次，不扩展查询条件。人工输入/刷新使旧识别结果失效。退出或身份变化取消旧任务；Cloudflare 不参与学校认证。

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
