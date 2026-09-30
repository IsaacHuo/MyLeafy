# MyLeafy Website

MyLeafy 官网、技术支持、隐私政策、分享落地页与 `/admin` 运营后台，部署在 Cloudflare Pages。

## 本地开发

```bash
npm ci
npm run dev
npm test
npm run build
```

Vite 开发服务器适合公开页面或 mock API 下的后台界面。`npm run build` 同时检查类型、静态网站和 Pages Functions 编译。`npm run dev:pages` 会构建网站并启动 Pages Functions；真实后台请求还需要绑定正在运行的 Worker。未绑定时代理明确返回服务不可用，不回退到旧 Supabase。

## 服务边界

- 浏览器只调用同域 `/api/admin/*`。管理 token 保存在 HttpOnly、Secure、SameSite Cookie，写入校验 Origin 和 CSRF。
- `MYLEAFY_ADMIN_API` 服务绑定连接 Worker 的 `AdminAPI` entrypoint。管理 API 不在 Worker 的公开 HTTP 路由暴露。
- `MYLEAFY_PUBLIC_API` 服务绑定连接同一 Worker 的默认入口，提供分享预览与可访问的文件。官网下载区通过同域 `/api/releases/android/{latest,download}` 读取此绑定的发行信息；测试网站不会调用生产下载接口。
- 生产两项绑定均指向 `myleafy-api-production`；隔离预览环境应指向 `myleafy-api-staging`。
- 网站运行时无需 Supabase URL、publishable key 或旧 `ADMIN_PROXY_SECRET`。数据库、邮件和签名密钥仅配置在 Worker Secrets，禁止以 `VITE_` 变量注入浏览器。

## Cloudflare Pages

- Project: `leafy`
- Root directory: `site`
- Build command: `npm run build`
- Output directory: `dist`
- Production domain: `myleafy.space`
- Support URL: `https://myleafy.space/support`
- Privacy Policy URL: `https://myleafy.space/privacy`
- Admin URL: `https://myleafy.space/admin`
- 发布切换时关闭 Git 自动生产部署，使用 GitHub 的 **Publish accepted Cloudflare version** 部署到原项目；项目变量为 `CLOUDFLARE_PAGES_PROJECT=leafy`。未完成 Cloudflare 设置核对前不能假定已关闭。

先在 staging 验收指定提交，正式部署依次运行数据库迁移、Worker、网站，并回读部署身份。`wrangler.staging.jsonc` / `wrangler.production.jsonc` 指定相应服务绑定，发布后核对环境一致。admin 仅管理 Android 的候选、发布、重试和撤回；iOS 由 Apple 管理。完整说明见 [交付与发布](../docs/operations/delivery.md)、[运营后台](../docs/engineering/admin-console.md) 和 [Cloudflare 后端](../docs/engineering/cloudflare-migration.md)。

`support@myleafy.space` 通过 Cloudflare Email Routing 转发；App 验证码由 Worker 调用 Resend 发送。
