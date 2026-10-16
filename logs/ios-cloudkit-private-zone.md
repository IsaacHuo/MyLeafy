# CloudKit 私有分区初始化返回错误 15

## 已确认的失败位置

2026-10-16 18:02–18:03，连接 hwf 后由用户点击 iCloud 重试。Console 的 CloudKit 日志显示：

- 请求经 `gateway.icloud.com.cn`；`CKDFetchRecordZonesOperation` 返回 `CKInternalErrorDomain 2000`、`CKHTTPStatus 500`。
- 紧接着出现 `Failed to fetch zone PCS` / `Refusing to save zone`，`CKDModifyRecordZonesOperation` 结束；此时尚未上传个人记录。
- 旧 App 只显示 `localizedDescription`，自身日志又全部使用 private，因此用户只能看到 `CKErrorDomain 15`。
- 当日真机 Debug 包有 CloudKit 容器权限，签名中缺少 `com.apple.developer.icloud-container-environment`；provisioning profile 则允许 Development/Production。

这些证据只能证明私有分区准备失败，不能单靠错误 15 推断用户没有登录、课程格式错误或生产 schema 没发布。错误 15 可以涉及参数，也可能是服务端拒绝，需要保留嵌套错误和请求编号。

## 排查方式

1. 对签名后的 `.app` 使用 `codesign -d --entitlements :-`，核对容器、环境、team；只看源 entitlement 文件不够。
2. 用 Console 选择已连接设备，筛选 CloudKit；在用户重试后读取同一时段的 zone/PCS/HTTP 错误。
3. 同步状态页的错误详情只输出安全元数据，不输出 CKRecord、数据正文、请求 headers 或凭据。
4. 现有 zone 不应每次同步都再次保存。先读取，只在 `zoneNotFound` 时创建；其它错误不得静默降级为重建。
5. 如明确指定环境后仍持续出现 PCS/HTTP 500，用请求编号在 CloudKit Console 或向 Apple 排查容器服务状态；不得把无签名构建或单机成功当双设备同步验收。

## iOS 分发签名拒绝额外的开发容器键

App Store Connect 返回 `Invalid Code Signing Entitlements`，明确拒绝主 App 签名中的 `com.apple.developer.icloud-container-development-container-identifiers`。该键虽然出现在 Apple 通用 entitlement 文档中，也可能通过本机开发签名，但不能据此视为 iOS 分发支持。不要将 provisioning profile 中出现的键全部复制进 App entitlement 文件。

iOS 主 App 仅声明 `com.apple.developer.icloud-container-identifiers`、`com.apple.developer.icloud-services` 和 `com.apple.developer.icloud-container-environment` 这三个 CloudKit 配置键；环境继续由 Debug/Release 分别指定 Development/Production。修正后必须重新 Archive，旧 archive/IPA 的签名不会随源文件修改而变化。核对 Release archive 的实际签名；本机签名通过不代表 App Store Connect 上传验证通过，也不代表 HTTP 500 已解决。

参考：[Apple 的 serverRejectedRequest 定义](https://developer.apple.com/documentation/cloudkit/ckerror/serverrejectedrequest)、[Apple DTS 对同类错误的排查说明](https://developer.apple.com/forums/thread/823303)、[CloudKit 环境 entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-container-environment)。
