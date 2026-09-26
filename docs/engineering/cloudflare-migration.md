# Cloudflare 后端迁移

## 当前边界

2026-09-26：按全新版本推进，iOS、网站和运营后台接入 Cloudflare；Android 暂不修改。新版代码在 main 继续开发。生产仍由 Supabase 承担，未冻结源写入、未切换 DNS、未删除旧服务。

## 实现

- Workers + Hono 提供 `/v1`；Better Auth 的签名 bearer 会话由 iOS URLSession/Keychain 保存。保留账号 UUID、密码哈希和长期 profile，允许重新登录，不兑换旧会话。
- D1 承担业务数据，原 RLS/RPC 授权在服务端显式检查。D1 batch 保证关联写入原子性；R2 使用不可变文件路径、一次性验证凭证及持久化清理任务。
- Durable Objects 发送变更信号，客户端重新拉取权威内容。Feed 和管理员预览共享筛选逻辑。
- Pages 使用 `MYLEAFY_ADMIN_API` 私有入口和 `MYLEAFY_PUBLIC_API` 绑定；管理员图片/附件预览的签名票据复核有效会话。后台操作覆盖通过静态清单核对。
- iOS 不再依赖 Supabase SDK。保留本地身份序列化键以保护本机数据；旧任务禁止跨后台提交。学校教务、WeatherKit、SwiftData、Widget 不迁到云端。
- Debug 默认 staging，Release 默认 `api.myleafy.space`。生产域名未切流前不能把 Release 构建视为生产就绪。

## 操作配置

受保护的本地 `.env.migration` 不进入 Git。Cloudflare 优先使用 `wrangler login`，迁移工具从 CLI 安全读取短期 OAuth token；也支持单独的 API Token。Supabase 连接强制使用完整 TLS 验证及项目 CA；Resend 域名为 myleafy.space，staging 仅给指定测试收件人发送邮件。AUTH_SECRET 与 MEDIA_SIGNING_SECRET 由部署时生成或保留已有值，不进入客户端。

先执行 `npm run typecheck`、`npm run check:contracts` 和 `wrangler deploy --env staging --dry-run`。按用户最新要求，最终验收采用静态检查和构建，设备行为由用户真机检查；不做模拟器交互验收。

生产 Pages 项目 `leafy` 的 Git 自动生产部署按用户要求保持开启；新后台服务绑定随部署配置维护。

## 数据与切流门槛

导出采用同一 PostgreSQL REPEATABLE READ 快照，schema 与逐表数据加密保存。大型共享课表 JSON 使用小批次读取。任何中断使整个数据库快照保持 incomplete，必须重新导出，不能拼接两次快照。文件单独下载和逐对象校验，数据库完成不代表文件备份完成。

完成备份后执行 files、verify、materialize，再对隔离 D1/R2 做导入与逐主键/哈希校验。实时生产源的演练快照不能代替维护窗口冻结写入后的最终快照。

切流前保留旧生产。开放新写入前失败可取消切流；开放后先冻结新写入并保存最新数据，采用同一新 API 的 Worker 回退和 D1/R2 恢复，不直接恢复过时旧库。旧 Supabase 与备份至少保留 30 天，满足数据校验、真机验收和发布安排后才退役。

## 验证状态

- 已验证：Cloudflare OAuth 与 staging/production D1/R2 访问；Supabase 数据库、Auth/Storage 读取；Resend 已验证域名；iOS arm64 Simulator 目标构建、网站构建及后台类型检查。
- 已部署：staging 与 production Worker、8 份 D1 migration、Resend Secrets；api.myleafy.space 绑定正式 Worker，Pages 生产服务绑定已配置，自动部署保持开启。数据库处于 read_only，尚未开放业务写入。
- 正在进行：完整生产加密备份、文件备份、转换校验及新 API 验收。
- 未完成：生产切换、真机验收、App Store 发布与旧服务退役。
