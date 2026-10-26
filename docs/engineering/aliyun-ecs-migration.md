# 阿里云 ECS 迁移

跟踪 [#53](https://github.com/IsaacHuo/MyLeafy/issues/53)。所有者确认迁移整套 Cloudflare 服务，允许维护中断，旧 Supabase 保留。后续补充要求包括权威 DNS。所有者于 2026-10-26 明确暂缓支持邮箱迁移，当前先完成官网、API、文件、数据库及发布链路，Cloudflare 邮件转发作为单独保留项。

## 目标与边界

- 北京 ECS：Ubuntu 24.04 x64、2 vCPU / 2 GiB、40 GiB 磁盘、3 Mbps。2026-10-26 只读核验剩余约 31 GiB，现有服务不占用网站端口。
- `myleafy.space` 提供官网，`www.myleafy.space` 永久重定向至同一官网并保留路径；`api.myleafy.space` 提供 `/v1`。保留原下载域名，避免已安装 Android 的发行链接失效。
- Node 24 LTS / Hono / Better Auth / better-sqlite3 / 本地对象目录 / WebSocket / node-cron；单进程、systemd，Caddy 提供入口。无数据库协议转换、双写或增量同步。
- 源码、服务部署、备案、DNS 切换和客户端验收分别记录。当前 Cloudflare 数据库仍是数据权威；2026-10-26 公共解析器已见阿里云 NS、无 A 记录，本机缓存仍见 Cloudflare。阿里云域名实名认证及域名核验均为 SUCCEED，解析记录尚未补齐，不能把此文当作已迁移证明。

## 运行与契约

SQLite 使用 WAL、外键约束与同步立即事务；业务批次和授权断言一起回滚。Better Auth 使用原账号数据和原认证密钥；测试覆盖备份恢复后签名 bearer 的身份连续性。对象写入先完成大小/哈希校验，再原子提交目录；对象键映射为固定摘要目录，不能穿越路径，已存在对象不可覆盖。保留原 ETag、内容类型、SHA-256 和 Range 行为。

只有官网路由可调用管理处理器；API 主机不挂载 `/admin`。网站继续通过 HttpOnly Cookie 和 CSRF 检查，服务端角色与审计不变。Caddy 重写真实客户端 IP，Node 清除不可信转发头。WebSocket 保留原 `changed/event_id` 与 ping/pong 协议，每分钟及投递前校验授权，失效时关闭连接；持久化 outbox 保留重试。

四项 Cron 沿用原 UTC 表达式与 `scheduled_runs` 幂等标识。进程关闭先停止调度、关闭 WebSocket，等待请求及后台任务排空后关闭 SQLite。

## 数据与切换

2026-10-26 生产只读盘点得到 71 张普通表、88,075 行、10 张 FTS5 虚拟表；这只是盘点时刻，不代表最终快照。源 Secret 值不写入报告。已有 `.env.migration` API Token 对 D1 返回 403，现有 Wrangler OAuth 可完成只读盘点。

导出以在线 `sqlite_schema`、列元数据及迁移记录为准，不用当前 migration 文件推断生产已应用版本。普通表按确定顺序导出，保留 rowid、int64、blob，目标端先导入数据，再建立搜索索引和触发器，核对逐表内容摘要、外键和完整性。R2 两个 bucket 的对象、元数据与发行 APK 原字节一并加密保存。

`--rehearsal` 导出明确标记非一致快照，不能用于生产恢复。`--quiesced` 要求 `SOURCE_FREEZE_REPORT` 与 Cloudflare 认证 API 查询到的 100% 活跃维护版本一致；不依赖迁移中的域名解析。该独立入口 `/health` 返回 503 和 `migration_source_frozen=true`，同时拒绝公开和 AdminAPI 请求，并停止 Cron 与旧实时连接。维护版本确认后，为全部普通表安装临时写入冻结触发器，最后原子设置冻结标记；旧版本在途认证、管理、发行或 Cron 请求也无法继续提交数据库写入。恢复到目标时先验证完整原始快照，再只移除迁移专用冻结表和触发器，保留目标 maintenance；源库继续冻结。最终导出前仍须排空在途文件上传和发行工作流。

网站与 App 首次备案条件满足、私有验收通过、所有者批准后，才停写最终导出、导入 ECS、更新 DNS 与域名绑定。DNS 迁至阿里云前完整保留 MX/TXT/CAA 等记录，核对 DNSSEC/DS，修改注册商 NS 后等待委派缓存收敛。传播期间源服务维持维护，只有目标接收新写入。新端开放写入后的回退必须先保护新数据，不能直接切回旧库。

## 备份与交付

操作入口见 [ECS 交付](../operations/ecs-delivery.md)。每日备份会短暂停止本环境服务，待排空后加密数据库、文件和运行配置；失败也恢复原先运行的服务。每日北京时间约 03:30 执行，完成快照保留 30 天。下载到 Mac 由所有者手动发起，不宣称已有自动异机备份。迁移前后必须实际下载并验证一份。

旧 Cloudflare 数据至少保留 7 天，清退需另行确认。新源码禁止执行旧 Cloudflare 发布脚本；源恢复应使用迁移前记录的源码/版本，不将 ECS 代码误发到 Worker。当前非邮件迁移的验收覆盖运行、存储、下载、网站/API DNS 和 CI 发布凭据。`support@myleafy.space` 的 Cloudflare 邮件转发、对应 MX/SPF/DKIM 与 Zone 暂不退役，不阻塞其他服务；不能因此宣称所有 Cloudflare 服务均已停用。验证码发信继续使用现有 Resend，不在本次暂缓范围内。

## 本轮证据与未完成项（2026-10-26）

生产演练包含 71 表、483 个媒体对象和 18 个发行对象，逐表恢复、外键、搜索、自增序列、对象哈希及数据库附件/发行引用校验通过；演练标记非一致，不能用于正式切换。ECS 私有实例通过 12 项真实 HTTP/WebSocket 检查，已演练每日备份停止/恢复服务；测试与生产 Secret 不混用。

DNS 导出已收到并完成 19 条记录的只读计划，支持邮件记录原值保留；新增真实 Cloudflare SOA 格式回归。GitHub Token 已只读核验仓库、工作流及私有候选记录，生产待上线配置已备齐；所有者确认使用新 RELEASE_PUBLISH_TOKEN，待正式切换时与 GitHub 共享密钥同步激活。独立 CI RAM 身份已创建并核对仅对目标 ECS 具有远程执行权限，staging/production 环境凭据已配置，完整自动部署验收另记。待完成：网站/App 备案、生产审批与最终停写导出/切换；支持邮箱迁移按所有者要求另行处理。正式 Android 签名摘要从现有发行元数据保留，不重新签名 APK。实际验证码送达、私有 GitHub 候选下载/发布和真实客户端验收尚未通过，不以网络可达或本地测试替代。
