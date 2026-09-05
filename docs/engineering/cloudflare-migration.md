# Cloudflare 后台迁移

本文件记录迁移分支的实现边界与运行步骤。生产权威后台仍为 Supabase，尚未切换。

## 已确认的边界

- 允许维护窗口。旧版 App 过渡保留，最终要求升级；不长期双写两个数据库。
- 北林学校身份继承沿用现有客户端证明方式；通用校园账户只可绑定当前已验证邮箱账号的 UUID。
- 北林绑定邮箱仅作通知联系方式，不能用于找回其他学校身份。
- iOS 使用原生 WeatherKit；Android 直接使用 Open-Meteo。遗留 `campus-weather` 不作为新后台必需能力，高德密钥不是迁移前置配置。
- Supabase 及备份至少保留 30 天。生产切换前必须完成真实数据/文件校验和反向恢复演练。

## 当前实现与证据

- `backend/` 使用 Hono、Better Auth、Workers、D1、R2 与 Durable Objects。业务 SQL 与授权在 Worker 中显式实现；没有公开 SQL 执行端点。
- 已加入身份初始化、资料、邮箱验证接入、账户删除、Feed、发帖/评论、通知、文件上传和凭证、部分社区互动、投票、课表分享、目录评分接口。
- D1 事务复核会话、profile、校园与维护状态；媒体引用通过短期凭证一次性附加，文件只能以服务端生成的不可变路径上传。
- D1 时间列统一为 UTC 六位小数，保留 PostgreSQL 微秒；FTS 更新仅由被索引字段变化触发，避免时间归一化触发器在首次插入时破坏 FTS。
- `myleafy-api-staging`、`myleafy-staging`、`myleafy-staging-files` 已存在。前五份迁移已在远端 D1 执行；之后新增迁移仍需按下方命令部署。
- 第一轮真实 staging 冒烟已通过匿名登录、重复初始化、发帖幂等、评论幂等计数、Feed、未登录拒绝与外键检查。脚本结束将 staging 恢复只读。合成资料的 `edu_id` 以 `cf-smoke-` 开头。
- iOS `MyLeafyBackendClient` 已加入 URLSession/Keychain 传输层并通过独立 Swift 类型检查；现有页面尚未切换到它。独立类型检查不能代替 iOS 构建或真机验收。
- Android 已加入 OkHttp/Keystore 传输层与针对性测试；本机缺少 Android SDK，Gradle 验证停在 SDK 发现阶段，尚未编译验证。管理端已有认证、权限投影和部分数据操作代码，尚未接通 Pages 代理。
- 本次阶段验证通过 Worker/工具类型检查、33 个业务测试和 11 个迁移测试。它们不代表未接入的客户端、管理端和生产切换已经完成。

仍需完成客户端全量接入、Android、管理端及分享页适配、剩余业务契约、完整权限/并发覆盖、真实数据迁移与生产切换。不能把现有 Worker 或健康检查当作完整迁移完成。

## 迁移工具

所有真实数据只保存在受限目录，备份块使用 AES-256-GCM 加密并绑定 backup ID 与块名。操作环境文件不得进入 App、Vite 或 Git。

```sh
cd backend
npm ci
npm run typecheck
npm test
npm run test:migration
node --env-file=.env.migration scripts/migration/preflight.mjs
node --env-file=.env.migration scripts/migration/export.mjs .local/backups
node --env-file=.env.migration scripts/migration/files.mjs .local/backups/BACKUP_ID
node --env-file=.env.migration scripts/migration/verify.mjs .local/backups/BACKUP_ID
node --env-file=.env.migration scripts/migration/materialize.mjs .local/backups/BACKUP_ID .local/converted.sqlite
node --env-file=.env.migration scripts/migration/r2-transfer.mjs staging .local/backups/BACKUP_ID
node --env-file=.env.migration scripts/migration/d1-transfer.mjs staging .local/converted.sqlite --replace-frozen-database
```

示例中的 `BACKUP_ID` 替换为导出结果。`PG_DUMP_BIN` 指向 PostgreSQL 17+ 的 `pg_dump`。数据库导出使用同一个 PostgreSQL snapshot；中途失败后必须重做数据库快照，不能把不同时间的数据页拼在一起。文件下载可在同一份冻结源快照下断点续跑。

最终同步使用新的完整源快照重新转换，然后执行 `d1-transfer.mjs staging NEW.sqlite --delta-from BASELINE.sqlite`。工具先验证目标仍等于 baseline，再生成包括硬删除的差异；不会仅依赖 `updated_at`。D1 完成后逐表逐主键校验并保持只读。R2 每个对象上传后重新读取验证 SHA-256；覆盖前备份原目标对象，不删除目标独有对象。

当前增量转换与正向导入不能替代尚待完成的 PostgreSQL/Auth 反向恢复工具。开放生产写入前，必须演练恢复切换后的新用户、修改后的密码、注销、文件、新增/删除内容以及对应外键和计数。

## 部署与配置

```sh
npx wrangler d1 migrations apply myleafy-staging --remote --env staging
npx wrangler deploy --env staging
npx wrangler secret bulk .local/staging-secrets.json --env staging
node --env-file=.env.migration scripts/staging-smoke.mjs
```

staging 和 production 分别设置 AUTH_SECRET、MEDIA_SIGNING_SECRET、EMAIL_API_KEY、EMAIL_FROM；staging 限制 TEST_EMAIL_RECIPIENT。旧会话兑换只使用服务端验证过的 Supabase 用户和已迁移身份。平台 invocation logs 已关闭，应用日志仅输出错误分类与 request ID，避免记录下载票据和请求正文。

本次本机 Cloudflare token 验证有效，D1/R2/Worker 资源访问成功。用户已自行升级 Workers Paid，控制台确认 Workers Paid 与 R2 Paid 均为活动状态。

Supabase 控制台曾显示 Unhealthy、数据库 TCP 连接超时及 Disk IO Budget 告警。本次执行过一次普通项目重启，之后轻量查询成功读取到 7,271 个 Auth 用户（其中 26 个密码账号）、2,332 份 profile、150 篇帖子、596 个 Storage 对象，数据库大小为 74,394,771 字节；随后连接和导出仍间歇失败。已从该项目控制台取得官方 Supabase Root 2021 CA，连接池的 TLS 校验问题已解决，但仍返回数据库不可用的 EAUTHQUERY。完整数据库备份和文件备份均未完成。

网络限制读取为开放 IPv4/IPv6；备份列表未返回可用备份且 PITR 未开启。没有修改生产业务表，没有切换生产或删除旧后台。为避免继续耗在重复连接排查上，先完成代码与契约验证；稳定的生产导出通路仍是切换阻塞。

真实导出仍需要可用的数据库连接或恢复 Supabase 的受支持导出入口；邮件送达需要 Resend 配置。生产域名默认 `api.myleafy.space`，尚未绑定或切流。
