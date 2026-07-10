# 邮箱绑定验证码投递设计

## 目标

北林账号绑定邮箱时，邮件只提供 App 内输入的验证码；邮箱链接不得直接把社区档案的 `bound_email` 标记为已绑定。

## 根因

`CommunityService.requestEmailVerification` 调用 Supabase Auth 的 email-change API，正确地生成可用 `verifyOTP(type: .emailChange)` 验证的令牌。线上 Auth 项目仍使用 Supabase 默认邮件模板，其中的 `{{ .ConfirmationURL }}` 会在点击后直接确认邮箱变更。随后 iOS 的 URL 回调和绑定页加载都会调用 `syncVerifiedEmailFromAuth()`，把已确认的 Auth 邮箱自动同步到 `profiles.bound_email`。

## 设计

1. 在 `supabase/config.toml` 声明 `auth.email.template.email_change`，并新增受版本控制的中文 HTML 模板。模板主题为“`MyLeafy 绑定邮箱验证码`”，只展示 `{{ .Token }}` 和 `{{ .NewEmail }}`，不得包含 `{{ .ConfirmationURL }}`、`{{ .TokenHash }}` 或可确认邮箱变更的链接。
2. `ProfileEmailBindingView` 不再在页面加载时同步 Auth 邮箱。`CommunityService.verifyEmailBinding(input:)` 是唯一将邮箱写入 `profiles.bound_email` 的 App 内路径。
3. 北林已有校园身份收到旧版 URL 回调时，仅提示用户回到 App 输入验证码，不再调用 `syncVerifiedEmailFromAuth()`。通用入口账号的现有回调登录语义不变。
4. 文档明确区分本地模板配置与托管 Supabase 项目的部署：托管项目需把同一主题和 HTML 粘贴到 Dashboard 的 Auth → Email Templates → Change email address，或通过 Management API 更新；`config.toml` 不会自动覆盖线上模板。

## 边界与兼容性

- 不新增邮箱密码登录，也不修改已验证邮箱到学号的解析服务。
- 旧版邮件链接在上线前的短暂存活期可能仍会改变 Supabase Auth 内部邮箱，但不会由 App 自动写入 `bound_email`；用户需重新发送验证码完成社区邮箱绑定。
- 自定义校园入口仍沿用其现有邮件回调登录，不受此变更影响。

## 验证

- 先添加 shell 回归检查，证明模板配置缺失时失败；实现后验证模板包含 `{{ .Token }}` 且不包含 `{{ .ConfirmationURL }}`。
- 运行现有 `EmailBindingAndAliasLoginTests`，并以 XcodeBuildMCP 构建 `leafy` scheme。
- 托管模板应用后，手动请求一次绑定邮件，确认主题和正文均为中文验证码且无确认链接。
