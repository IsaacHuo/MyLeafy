# MyLeafy Website

MyLeafy 的 App Store 技术支持和隐私政策静态站。

## Local

```bash
npm install
cp .env.example .env
npm run build
npm run preview
```

`/admin` 是独立懒加载的 React-admin 生产运营后台。浏览器只调用 `/api/admin/*` 同域 Pages Function，Supabase 管理 token 只保存在 HttpOnly Cookie 中。后台 Pages Function 需要配置：

```text
SUPABASE_URL=...
SUPABASE_PUBLISHABLE_KEY=...
ADMIN_PROXY_SECRET=...
```

`ADMIN_PROXY_SECRET` 必须同时配置为 Supabase Edge Function secret。分享页继续通过 `share-preview` 获取脱敏卡片摘要；完整后台部署说明见 `docs/admin-console.md`。

置顶和客户端 Feed 预览依赖已部署的 `admin-community`、`community-feed` Edge Functions，以及包含 `community_post_pins` 和 `community_feed_v1` 的最新 migrations。帖子和共享课表链接卡片依赖已部署的 `share-preview` Edge Function。

## Cloudflare Pages

- Root directory: `site`
- Build command: `npm run build`
- Output directory: `dist`
- Production domain: `myleafy.space`
- Support URL: `https://myleafy.space/support`
- Privacy Policy URL: `https://myleafy.space/privacy`
- Admin URL: `https://myleafy.space/admin`
- Admin Pages Function variables: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `ADMIN_PROXY_SECRET`
- Legacy `VITE_*` values仅供分享 Pages Function 兼容，不再被后台浏览器代码读取。

`support@myleafy.space` 应通过 Cloudflare Email Routing 转发到实际收件邮箱。
