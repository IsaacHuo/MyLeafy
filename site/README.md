# MyLeafy Website

MyLeafy 官网、技术支持、隐私政策、分享落地页与 `/admin` 运营后台，部署在 Cloudflare Pages。

## 本地开发

```bash
npm ci
npm run dev
npm test
npm run build
```

Vite 开发服务器适合公开页面或 mock API 下的后台界面。`npm run dev:pages` 会构建网站并启动 Pages Functions；真实后台请求还需要绑定正在运行的 Worker。未绑定时代理明确返回服务不可用，不回退到旧 Supabase。

## 服务边界

- 浏览器只调用同域 `/api/admin/*`。管理 token 保存在 HttpOnly、Secure、SameSite Cookie，写入校验 Origin 和 CSRF。
- `MYLEAFY_ADMIN_API` 服务绑定连接 Worker 的 `AdminAPI` entrypoint。管理 API 不在 Worker 的公开 HTTP 路由暴露。
- `MYLEAFY_PUBLIC_API` 服务绑定连接同一 Worker 的默认入口，提供分享预览与可访问的文件。
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
- Git 自动生产部署保持开启。

先部署通过验证的 Worker，再发布依赖其接口的网站。服务绑定在 Pages 项目中配置，发布后确认绑定目标与环境一致。完整说明见 [运营后台](../docs/engineering/admin-console.md) 和 [Cloudflare 后端](../docs/engineering/cloudflare-migration.md)。

`support@myleafy.space` 通过 Cloudflare Email Routing 转发；App 验证码由 Worker 调用 Resend 发送。
