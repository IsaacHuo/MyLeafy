# MyLeafy Website

MyLeafy 的 App Store 技术支持和隐私政策静态站。

## Local

```bash
npm install
cp .env.example .env
npm run build
npm run preview
```

`/admin` 是生产社区运营后台入口，包含手册、总览、内容审核、帖子置顶、客户端 Feed 预览、反馈、公告、名录和管理员模块。后台登录需要配置：

```text
VITE_SUPABASE_URL=...
VITE_SUPABASE_PUBLISHABLE_KEY=...
```

这两个变量用于后台和分享页调用 Supabase Edge Functions。分享页会通过 `share-preview` 获取脱敏卡片摘要。

置顶和客户端 Feed 预览依赖已部署的 `admin-community`、`community-feed` Edge Functions，以及包含 `community_post_pins` 和 `community_feed_v1` 的最新 migrations。帖子和共享课表链接卡片依赖已部署的 `share-preview` Edge Function。

## Cloudflare Pages

- Root directory: `site`
- Build command: `npm run build`
- Output directory: `dist`
- Production domain: `myleafy.space`
- Support URL: `https://myleafy.space/support`
- Privacy Policy URL: `https://myleafy.space/privacy`
- Admin URL: `https://myleafy.space/admin`
- Environment variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`
- Pages Functions also read `SUPABASE_URL` when available, and fall back to `VITE_SUPABASE_URL`.

`support@myleafy.space` 应通过 Cloudflare Email Routing 转发到实际收件邮箱。
