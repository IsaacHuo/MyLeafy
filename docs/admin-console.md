# MyLeafy 运营后台

生产后台位于 `/admin`。官网仍是 Vite 应用，后台代码通过 `lazy()` 独立加载；后台使用 React-admin 5、MUI 和按模块加载的 ECharts 6，不影响官网首屏包。

## 架构与安全边界

浏览器只请求 Cloudflare Pages Function：

- `POST /api/admin/login`
- `GET /api/admin/me`
- `POST /api/admin/logout`
- `POST /api/admin/actions`
- `POST /api/admin/export`

登录成功后，Pages Function 把 12 小时 Supabase 管理会话写入 `leafy_admin_session` Cookie：`HttpOnly; Secure; SameSite=Strict; Path=/api/admin`。响应不会把 token 返回给 JavaScript；新后台启动时还会删除旧版 `leafy-admin-session` localStorage token。

所有 API 请求校验同源和 `X-Leafy-Admin-CSRF: 1`，并携带 request ID。只有 401 清理本地身份；403、网络错误和后端错误保留会话并显示错误和 request ID。Edge Function 仍是最终认证、角色授权、校园范围、参数校验和审计边界，不修改普通 App 用户 RLS。

## 环境变量

Cloudflare Pages 的 Production 和 Preview 环境配置：

```text
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
ADMIN_PROXY_SECRET=<至少 32 字节随机值>
```

同一个 `ADMIN_PROXY_SECRET` 写入 Supabase Edge Function secrets：

```bash
supabase secrets set ADMIN_PROXY_SECRET='<same-random-secret>'
```

本地 Pages Function 调试使用 `site/.dev.vars`（不要提交）：

```text
SUPABASE_URL=...
SUPABASE_PUBLISHABLE_KEY=...
ADMIN_PROXY_SECRET=...
```

```bash
cd site
npm ci
npm run dev:pages
```

普通 `npm run dev` 只启动 Vite，适合用 mock API 进行前端测试；真实登录需要 Pages Function 链路。

## 角色与资源

- `viewer`：总览、搜索、列表和详情；不能写入、批量操作或导出。
- `operator`：现有运营动作；可导出内容、举报、公告和名录白名单资源。
- `super_admin`：全部能力，并可管理管理员、会话、审计及敏感导出。

后台资源分为：总览/手册，学校与社区内容，考研与名录，学期/国家日历运行配置，以及管理员/会话/审计。学校页保留“申请/学校空间”页签，考研页保留“公开来源/用户线索”页签。列表筛选、排序和分页写入 URL，分页为 20/50/100。

帖子页保留详情、全局/分类置顶、取消置顶、批量下架/恢复和客户端 Feed 预览。删除、禁言、审核、会话撤销等操作使用带影响说明和校验的对话框，不使用原生 `prompt`/`confirm`，也不做乐观更新。

全局搜索长度为 2–100 字符，覆盖帖子、评论、用户、反馈、教师、课程、菜品和考研来源；每类最多 8 条、总计最多 40 条，继承当前角色和校园范围，摘要不返回邮箱、联系方式或学号。

CSV 导出只接受 `{ resource, filters, sort? }`。`admin-export` 使用服务端资源/字段白名单、校园和角色校验，最多返回 10,000 行，输出 UTF-8 BOM，并防止电子表格公式注入。每次导出记录资源、范围和行数。

## 数据库与函数部署

部署顺序固定为：前向 migration → 兼容 Edge Functions → Cloudflare 环境变量/Pages Function → 网站。

```bash
supabase db push
supabase functions deploy admin-login
supabase functions deploy admin-me
supabase functions deploy admin-logout
supabase functions deploy admin-community
supabase functions deploy admin-export
```

本次 migration 是 `20260710120000_admin_security_runtime.sql`，包含登录限流、90 天保留、审计元数据、搜索索引及学期/国家日历原子激活 RPC。`admin_login_attempts` 只授权 `service_role`。

如果 CLI 远程连接失败，在 Supabase Dashboard 按顺序操作：

1. SQL Editor 新建查询，完整执行 migration 文件并确认无错误。
2. Edge Functions 分别部署上述五个目录；在 Secrets 中设置 `ADMIN_PROXY_SECRET`。
3. Cloudflare Pages Settings → Variables and Secrets 设置三个变量，重新部署网站。
4. 不要在浏览器或普通用户角色中配置 `service_role`。

## 验证、发布与回滚

本地检查：

```bash
cd site
npm run typecheck
npm test
npm run build
npm run test:e2e

cd ..
deno check supabase/functions/admin-login/index.ts \
  supabase/functions/admin-me/index.ts \
  supabase/functions/admin-logout/index.ts \
  supabase/functions/admin-community/index.ts \
  supabase/functions/admin-export/index.ts
deno test --allow-read=supabase/functions/admin-community/index.ts \
  supabase/functions/_shared/admin-permissions.test.ts \
  supabase/functions/_shared/admin-csv.test.ts \
  supabase/functions/admin-community/admin-community.contract.test.ts
bash supabase/tests/verify_admin_security_runtime_migration.sh
supabase db reset
supabase test db
```

生产部署后用三种角色做只读冒烟，并执行一项可逆写操作核对 `request_id`、`outcome`、`duration_ms` 和 `audit_logged`。浏览器 Application 面板中不得出现后台 token。

失败时回滚 Cloudflare Pages 和 Edge Functions 到上一部署；数据库 migration 保持向前兼容，不做破坏性回滚。回滚后旧前端仍可调用保留的 60 个 action 名称。
