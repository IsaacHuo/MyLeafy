# MyLeafy Website

官网、技术支持、隐私政策、分享落地页与 `/admin` 运营后台由北京 ECS 的 Caddy 和 Node 提供。

## 本地开发与验证

```bash
npm ci
npm run dev
npm run typecheck
npm test
npm run build
npm run test:e2e
```

Vite 用于公开页面和 mock API 界面开发。实际同域服务由 Node 组合 `site/functions/` 中的处理器提供；保留目录名和接口，运行时不依赖 Pages/Worker 服务绑定。私有与公开 staging 见 [ECS 交付](../docs/operations/ecs-delivery.md)。

## 服务边界

- 浏览器只调用同域 `/api/admin/*`，管理会话保存在 HttpOnly、Secure、SameSite Cookie；写入核对 Origin 和 CSRF。
- Node 内部调用管理处理器，API 域名不开放直接管理入口；数据库、邮件、签名与 GitHub 密钥只在服务器受保护配置中。
- `/api/releases/android/{latest,download}` 与分享页使用相同环境的内部公开 API，staging 不回退生产。
- 网站无需 Supabase 配置；禁止将任何运行 Secret 放进 `VITE_` 变量。

## 部署与备案

生产为 `https://myleafy.space`，www 保留路径跳转；支持、隐私和后台分别为 `/support`、`/privacy`、`/admin`。staging 为 `https://staging.myleafy.space`。

使用 **Prepare or publish accepted ECS version**，先完整验收指定提交的 staging，再经所有者批准部署同一压缩包到 production。网站 `/release.json` 与 API `/health` 必须显示同一环境和提交。旧 Cloudflare 工作流已停用，历史 Pages 配置仅作源迁移/恢复记录。

官网展示网站备案 `桂ICP备2024050172号-4` 及 App 备案 `桂ICP备2024050172号-5A`。本轮所有者确认 App/网站正常；没有重新构建或签名移动端。

`support@myleafy.space` 已迁至阿里邮箱免费版，所有者确认收信与回复成功，登录 [阿里邮箱](https://qiye.aliyun.com/)。Cloudflare Email Routing 已关闭；App 验证码仍由 ECS 调用 Resend。生产数据及服务器配置的换机手册见 [Configuration](https://github.com/IsaacHuo/Configuration/tree/main/myleafy-ecs)。
