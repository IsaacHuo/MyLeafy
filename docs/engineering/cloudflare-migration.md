# Cloudflare 后端迁移

## 当前边界

2026-09-26：按全新版本推进，iOS、网站和运营后台接入 Cloudflare；Android 暂不修改。新版代码在 main 继续开发。生产仍由 Supabase 承担，未冻结 Supabase 源写入、未删除旧服务；新 API 子域已绑定 Cloudflare。旧版 App 继续使用 Supabase，新版先由用户真机验证；官网/运营后台接入 Cloudflare 已由用户明确接受。两套数据暂不互相同步。

## 实现

- Workers + Hono 提供 `/v1`；Better Auth 的签名 bearer 会话由 iOS URLSession/Keychain 保存。保留账号 UUID、密码哈希和长期 profile，允许重新登录，不兑换旧会话。
- D1 承担业务数据，原 RLS/RPC 授权在服务端显式检查。D1 batch 保证关联写入原子性；R2 使用不可变文件路径、一次性验证凭证及持久化清理任务。
- Durable Objects 发送变更信号，客户端重新拉取权威内容。Feed 和管理员预览共享筛选逻辑。
- Pages 使用 `MYLEAFY_ADMIN_API` 私有入口和 `MYLEAFY_PUBLIC_API` 绑定；管理员图片/附件预览的签名票据复核有效会话。后台操作覆盖通过静态清单核对。
- iOS 不再依赖 Supabase SDK。保留本地身份序列化键以保护本机数据；旧任务禁止跨后台提交。学校教务、WeatherKit、SwiftData、Widget 不迁到云端。
- iOS 默认连接 `api.myleafy.space`，与新官网后台使用同一套 Cloudflare 数据。隔离调试使用 `api-staging.myleafy.space`，不依赖当前网络解析异常的 workers.dev。

## 操作配置

受保护的本地 `.env.migration` 不进入 Git。Cloudflare 优先使用 `wrangler login`，迁移工具从 CLI 安全读取短期 OAuth token；也支持单独的 API Token。Supabase 连接强制使用完整 TLS 验证及项目 CA；Resend 域名为 myleafy.space，staging 仅给指定测试收件人发送邮件。AUTH_SECRET 与 MEDIA_SIGNING_SECRET 由部署时生成或保留已有值，不进入客户端。

先执行 `npm run typecheck`、`npm run check:contracts` 和 `wrangler deploy --env staging --dry-run`。按用户最新要求，最终验收采用静态检查和构建，设备行为由用户真机检查；不做模拟器交互验收。

生产 Pages 项目 `leafy` 的 Git 自动生产部署按用户要求保持开启；新后台服务绑定随部署配置维护。

## 数据与切流门槛

导出采用同一 PostgreSQL REPEATABLE READ 快照，schema 与逐表数据加密保存。大型共享课表 JSON 使用小批次读取。任何中断使整个数据库快照保持 incomplete，必须重新导出，不能拼接两次快照。文件单独下载和逐对象校验，数据库完成不代表文件备份完成。

完成备份后执行 files、verify、materialize，再对隔离 D1/R2 做导入与逐主键/哈希校验。实时生产源的演练快照不能代替维护窗口冻结写入后的最终快照。

切流前保留旧生产。开放新写入前失败可取消切流；开放后先冻结新写入并保存最新数据，采用同一新 API 的 Worker 回退和 D1/R2 恢复，不直接恢复过时旧库。旧 Supabase 与备份至少保留 30 天，满足数据校验、真机验收和发布安排后才退役。

## 验证状态

- 本次源快照：2026-09-26 20:37（上海时间），backup ID `6a541f00-79e4-4a19-9b59-449707f47779`。数据库与文件均已加密备份；首次失败的快照保持 incomplete，未用于导入。
- 已完成：源备份校验（53 个数据集、33,188 行及 623 个文件）、SQLite 转换、按依赖顺序的完整重放、D1 的 53 张目标表逐主键内容校验与外键检查、623 个 R2 对象回读 SHA-256 校验。导入包含新的认证表，源数据集与目标表不是一一对应；旧客户端及管理员会话不迁移。
- Cloudflare production 已切为 active；官网／运营后台和新 iOS 共用 `api.myleafy.space`。staging 保留隔离测试用途。旧 Supabase 保持运行且未写入或冻结，当前不做双向同步。
- iOS 静态检查、Simulator 编译目标构建、hwf 真机签名构建和签名校验通过，新包已安装到 hwf（iPhone 17 Pro）。没有模拟器点选验收，真实使用流程由用户验证。曾尝试的测试目标构建被既有缓存协议隔离冲突阻断，随后按用户要求不继续 XCTest。
- Worker 类型检查、73 个后台操作静态覆盖检查、网站构建通过；GitHub 的后端、网站、仓库安全及 iOS CI 已通过相应提交检查。Resend 配置和域名已验证、Secrets 已部署，实际验证码送达待用户真机验证。
- 未进行 App Store 发布、旧服务退役或新写入后的恢复演练。真实用户开始在 Cloudflare 写入后，不得用旧快照直接覆盖新库；保留备份至少 30 天。
- 本机的加密备份及验收报告在 `backend/.local/`，密钥在独立的 `.env.migration`，均被 Git 忽略。原有本地化文件及 Xcode Cloud 未提交文件保留。
