# Cloudflare 后端迁移

## 当前边界

2026-09-26：按全新版本推进，iOS、网站和运营后台接入 Cloudflare；Android 暂不修改。新版代码在 main 继续开发。新版生产由 Cloudflare 承担；旧 Supabase 独立继续服务旧版，未冻结源写入或删除旧服务。旧版 App 继续使用 Supabase，新版先由用户真机验证；官网/运营后台接入 Cloudflare 已由用户明确接受。两套数据暂不互相同步。

## 实现

- Workers + Hono 提供 `/v1`；Better Auth 的签名 bearer 会话由 iOS URLSession/Keychain 保存。保留账号 UUID、密码哈希和长期 profile，允许重新登录，不兑换旧会话。
- D1 承担业务数据，原 RLS/RPC 授权在服务端显式检查。D1 batch 保证关联写入原子性；R2 使用不可变文件路径、一次性验证凭证及持久化清理任务。
- Durable Objects 发送变更信号，客户端重新拉取权威内容。Feed 和管理员预览共享筛选逻辑。
- Pages 使用 `MYLEAFY_ADMIN_API` 私有入口和 `MYLEAFY_PUBLIC_API` 绑定；管理员图片/附件预览的签名票据复核有效会话。后台操作覆盖通过静态清单核对。
- iOS 不再依赖 Supabase SDK。保留本地身份序列化键以保护本机数据；旧任务禁止跨后台提交。学校教务、WeatherKit、SwiftData、Widget 不迁到云端。
- iOS 默认连接 `api.myleafy.space`，与新官网后台使用同一套 Cloudflare 数据。隔离调试使用 `api-staging.myleafy.space`，不依赖当前网络解析异常的 workers.dev。

## 操作配置

受保护的本地 `.env.migration` 不进入 Git。Cloudflare 优先使用 `wrangler login`，迁移工具从 CLI 安全读取短期 OAuth token；也支持单独的 API Token。Supabase 连接强制使用完整 TLS 验证及项目 CA；Resend 域名为 myleafy.space，staging 仅给指定测试收件人发送邮件。AUTH_SECRET 与 MEDIA_SIGNING_SECRET 由部署时生成或保留已有值，不进入客户端。

先执行 `npm run typecheck`、`npm run check:contracts` 和 `wrangler deploy --env staging --dry-run`。按用户最新要求，客户端验收采用静态检查和构建，后端逻辑使用隔离数据库回归测试，设备行为由用户真机检查；不做模拟器交互验收。

生产 Pages 项目 `leafy` 的发布流程改为 [交付与发布](../operations/delivery.md)：相关 main 提交经 CI 准备 staging，用户批准指定提交后再部署 production。首次切换需要关闭 Pages Git 自动生产部署并配置 Environment 凭据；设置核对完成前不能假定已关闭。服务绑定由分环境 Wrangler 配置维护。

## 数据与切流门槛

导出采用同一 PostgreSQL REPEATABLE READ 快照，schema 与逐表数据加密保存。大型共享课表 JSON 使用小批次读取。任何中断使整个数据库快照保持 incomplete，必须重新导出，不能拼接两次快照。文件单独下载和逐对象校验，数据库完成不代表文件备份完成。

完成备份后执行 files、verify、materialize，再对隔离 D1/R2 做导入与逐主键/哈希校验。当前采用快照后两套服务并行运行，未执行旧版整体切流。后续若需再次合并数据，必须单独设计冲突处理与增量同步，不能重放旧快照覆盖已有新写入。

新版已开放写入。若需回退，先保护新增数据，采用同一 API 的 Worker 回退及 D1/R2 恢复，不直接切回过时旧库。旧 Supabase 持续服务旧版，退役需要另行安排；加密备份至少保留 30 天。

## 验证状态

- 本次源快照：2026-09-26 20:37（上海时间），backup ID `6a541f00-79e4-4a19-9b59-449707f47779`。数据库与文件均已加密备份；首次失败的快照保持 incomplete，未用于导入。
- 已完成：源备份校验（53 个数据集、33,188 行及 623 个文件）、SQLite 转换、按依赖顺序的完整重放、D1 的 53 张目标表逐主键内容校验与外键检查、623 个 R2 对象回读 SHA-256 校验。导入包含新的认证表，源数据集与目标表不是一一对应；旧客户端及管理员会话不迁移。
- Cloudflare production 已切为 active；官网／运营后台和新 iOS 共用 `api.myleafy.space`。staging 保留隔离测试用途。旧 Supabase 保持运行且未写入或冻结，当前不做双向同步。
- iOS 静态检查、Simulator 编译目标构建、hwf 真机签名构建和签名校验通过，用户已自行安装并开始真机检查。完整 CI 已修复缓存协议测试隔离冲突，578 个 XCTest 中 577 通过、1 跳过；学校与设备真实使用流程仍由用户验收。
- Worker 类型检查、76 个后台操作静态覆盖检查、网站构建通过；GitHub 的统一 CI 已通过全范围检查。Resend 配置和域名已验证、Secrets 已部署，实际验证码送达待用户真机验证。
- 未进行 App Store 发布、旧服务退役或新写入后的恢复演练。真实用户开始在 Cloudflare 写入后，不得用旧快照直接覆盖新库；保留备份至少 30 天。
- 本机的加密备份及验收报告在 `backend/.local/`，密钥在独立的 `.env.migration`，均被 Git 忽略。本地配置与备份不随代码推送。

## 接口与数据复核

已补充发布状态恢复、媒体重复提交与过期凭证、UUID 大小写、举报请求体、资料显式清空、通知计数和后台操作回归。生产 D1 只读检查覆盖完整性、外键、互动与评分计数、身份关联、已发布媒体数量及清理失败记录，均未发现不一致；检查未改写线上内容。证据在受保护的 `backend/.local/database-audit.json`，可复用排查原则见 [接口契约排查](../../logs/2026-09-26-cloudflare-client-contracts.md)。

代码验证通过不替代真机全流程或新写入后的恢复演练。当前仍保留旧服务，不做自动退役。
