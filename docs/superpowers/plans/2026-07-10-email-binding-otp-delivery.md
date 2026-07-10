# 邮箱绑定验证码投递 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让邮箱绑定邮件只提供 App 内 OTP，并防止 URL 回调自动写入已绑定邮箱。

**Architecture:** Supabase 继续负责产生和校验 `email_change` OTP；受版本控制的 Auth 邮件模板决定邮件内容。iOS 只在 `CommunityService.verifyEmailBinding(input:)` 成功后写入 `profiles.bound_email`，不会从深链或视图加载自动同步。

**Tech Stack:** Swift 6、SwiftUI、Supabase Swift、Supabase CLI TOML/HTML 模板、XCTest、zsh。

## Global Constraints

- 最低 iOS 版本为 17，不新增依赖。
- 邮箱仍只作为北林教务账号登录别名，保留校园网、教务密码和验证码要求。
- `pending_bound_email` 不能用于登录，只有 `verifyOTP(type: .emailChange)` 成功后的 `bound_email` 可用于别名解析。
- 模板中必须包含 `{{ .Token }}`，不得包含 `{{ .ConfirmationURL }}`、`{{ .TokenHash }}` 或确认链接。
- 托管 Supabase 项目需要单独应用同一模板；本地 `config.toml` 只影响本地 Auth 服务。

---

### Task 1: Add a regression check and source-controlled Auth template

**Files:**
- Create: `supabase/templates/email-change-otp.html`
- Create: `supabase/tests/check-email-change-otp-template.sh`
- Modify: `supabase/config.toml:22-30`

**Interfaces:**
- Consumes: Supabase Auth template variables `{{ .Token }}` and `{{ .NewEmail }}`.
- Produces: `auth.email.template.email_change` local configuration with a deterministic HTML source file.

- [ ] **Step 1: Write the failing regression check**

Create `supabase/tests/check-email-change-otp-template.sh`:

```zsh
#!/usr/bin/env zsh
set -euo pipefail

template_path="supabase/templates/email-change-otp.html"
grep -Fq '[auth.email.template.email_change]' supabase/config.toml
grep -Fq 'subject = "MyLeafy 绑定邮箱验证码"' supabase/config.toml
grep -Fq 'content_path = "./supabase/templates/email-change-otp.html"' supabase/config.toml
grep -Fq '{{ .Token }}' "$template_path"
grep -Fq '{{ .NewEmail }}' "$template_path"
if grep -Fq '{{ .ConfirmationURL }}' "$template_path" || grep -Fq '{{ .TokenHash }}' "$template_path"; then
  exit 1
fi
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `zsh supabase/tests/check-email-change-otp-template.sh`

Expected: non-zero exit because the config section and template file do not yet exist.

- [ ] **Step 3: Add the minimal template configuration and HTML**

Add these settings after `[auth]` in `supabase/config.toml`:

```toml
[auth.email]
otp_length = 6
otp_expiry = 3600

[auth.email.template.email_change]
subject = "MyLeafy 绑定邮箱验证码"
content_path = "./supabase/templates/email-change-otp.html"
```

Create the HTML template with a Chinese title, `{{ .NewEmail }}`, a prominent `{{ .Token }}`, a one-hour expiry notice, and no confirmation URL or clickable confirmation action.

- [ ] **Step 4: Run the check to verify it passes**

Run: `zsh supabase/tests/check-email-change-otp-template.sh`

Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add supabase/config.toml supabase/templates/email-change-otp.html supabase/tests/check-email-change-otp-template.sh
git commit -m "fix(auth): send email binding OTP template"
```

### Task 2: Restrict binding completion to the App OTP path

**Files:**
- Modify: `leafy/Features/Profile/Presentation/ProfileEmailBindingView.swift:125-129`
- Modify: `leafy/App/leafyApp.swift:221-233`

**Interfaces:**
- Consumes: `CommunitySessionManager.verifyEmailBinding(email:code:)`.
- Produces: `profiles.bound_email` changes only after the existing `CommunityService.verifyEmailBinding(input:)` OTP call succeeds.

- [ ] **Step 1: Preserve the failing behavior in the regression check output**

Run: `rg -n 'syncVerifiedEmailFromAuth' leafy/Features/Profile/Presentation/ProfileEmailBindingView.swift leafy/App/leafyApp.swift`

Expected: the command finds both automatic-sync call sites before they are removed.

- [ ] **Step 2: Remove automatic sync on the binding page**

Keep bootstrap and email field seeding in the `.task`, but remove:

```swift
await sessionManager.syncVerifiedEmailFromAuth()
```

- [ ] **Step 3: Reject legacy URL completion for campus identities**

In the existing non-custom campus branch of `handleCustomCampusAuthCallback(_:)`, replace the sync call and success message with:

```swift
authCallbackMessage = L10n.text(
    "邮箱绑定请回到 App 输入邮件验证码完成。",
    language: .zhHans
)
return
```

Do not change the branch that persists a custom-campus Auth session.

- [ ] **Step 4: Verify the automatic-sync call sites are absent**

Run: `rg -n 'syncVerifiedEmailFromAuth' leafy/Features/Profile/Presentation/ProfileEmailBindingView.swift leafy/App/leafyApp.swift`

Expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add leafy/Features/Profile/Presentation/ProfileEmailBindingView.swift leafy/App/leafyApp.swift
git commit -m "fix(auth): require OTP for campus email binding"
```

### Task 3: Document hosted template deployment and verify the app

**Files:**
- Modify: `docs/supabase.md:23-38`
- Test: `leafyTests/EmailBindingAndAliasLoginTests.swift`

**Interfaces:**
- Consumes: `supabase/templates/email-change-otp.html`.
- Produces: explicit hosted Supabase deployment instructions and build/test evidence.

- [ ] **Step 1: Update the deployment documentation**

State that hosted projects must copy the exact subject and HTML from `supabase/templates/email-change-otp.html` into Dashboard → Auth → Email Templates → Change email address, and that the template must contain `{{ .Token }}` but not `{{ .ConfirmationURL }}`.

- [ ] **Step 2: Run focused validation**

Run:

```bash
zsh supabase/tests/check-email-change-otp-template.sh
plutil -lint leafy/Resources/Info.plist
```

Expected: both commands exit 0.

- [ ] **Step 3: Build and test the iOS target**

Use XcodeBuildMCP with the `leafy` scheme and a fresh DerivedData profile:

```text
build_sim → SUCCEEDED
test_sim onlyTesting=leafyTests/EmailBindingAndAliasLoginTests → 6 tests, 0 failures
```

- [ ] **Step 4: Commit**

```bash
git add docs/supabase.md docs/superpowers/specs/2026-07-10-email-binding-otp-delivery-design.md docs/superpowers/plans/2026-07-10-email-binding-otp-delivery.md
git commit -m "docs: document email binding OTP deployment"
```
