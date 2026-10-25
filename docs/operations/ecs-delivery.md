# ECS 交付与迁移操作

设计、数据门槛与边界见 [迁移说明](../engineering/aliyun-ecs-migration.md)。当前是否已上线以 CURRENT 和实际部署报告为准。

## 目录与配置

- `/opt/myleafy/<environment>/releases/<commit>`：构建产物；`current` 原子链接。
- `/var/lib/myleafy/<environment>`：SQLite、私有 files、公开 releases、维护标记和恢复报告。
- `/etc/myleafy/<environment>.env`：0600 运行配置，保留原生产认证与媒体签名 Secret；测试和生产独立。
- `/etc/myleafy/<environment>.backup.env`：0600，仅包含 BACKUP_ENCRYPTION_KEY；密钥在服务器之外单独保留。
- `/var/backups/myleafy/<environment>`：加密快照及 tar / SHA-256；备份不是公开网站文件。

bootstrap 只安装 Node 24.22.1、Caddy 2.11.7、系统用户和目录；不启动公网入口，不覆盖已存在配置。Node 使用 SHA-256，Caddy 官方清单使用 SHA-512，失败即停止。私有 Caddy 配置只监听 127.0.0.1:8081，另保存为 `/etc/myleafy/Caddyfile.private`。公开配置须备案后启用，继续导入该私有入口用于后续受控验收；公开 staging 启用时将其 SITE_ORIGIN 改为 https://staging.myleafy.space。www 跳转主域，下载域名继续服务原 APK。

## 数据操作（仓库根目录）

使用 Node 24。凭据从受保护 env 文件载入；现有 Wrangler OAuth 时可将旧 CLOUDFLARE_API_TOKEN 留空。所有目标目录必须是新目录。

```sh
node --env-file=backend/.env.migration backend/scripts/ecs/inventory.mjs production
node --env-file=backend/.env.migration backend/scripts/ecs/export.mjs staging PRIVATE_BACKUP --rehearsal
node --env-file=backend/.env.migration backend/dist/restore.mjs PRIVATE_BACKUP EMPTY_DATA_DIRECTORY --rehearsal
```

restore 默认保留 `maintenance`，失败保留 `restore-failed`，不激活残缺数据。完成逐表/文件校验后，先做备份恢复演练，再由操作者接通私有验收。待应用 migration 单独执行 `node backend/scripts/ecs/migrate.mjs DATABASE_PATH`，须先停服务和备份。该工具保留 `d1_migrations` 记录，不能对已建结构重放全部历史 SQL。

最终生产导出只在备案和验收均满足后执行：使用 `freeze-source.mjs` 和独立 `backend/cutover/maintenance.ts` 冻结现有 Worker 的全部入口，保存报告并确认在途任务结束，通过 `SOURCE_FREEZE_REPORT` 指定报告，以 `--quiesced` 导出，再 `--production` 恢复。冻结工具会阻断普通表的全部写入；不完整报告不能用于最终快照。目标先核对原始快照，再删除专用冻结机制，默认仍处于 maintenance。若目标从未开放写入，先停目标，再显式执行 `recover-source.mjs FREEZE_REPORT --confirmed-no-target-writes` 恢复源冻结机制与记录的旧代码；DNS 恢复另行处理。目标已接收新写入时禁止直接执行此恢复。不要为导出在源库删除 FTS 表。备份中原始运行配置可用同一备份密钥及 AAD `ecs-runtime-env-v1` 解密，不能把解密结果写入报告。

生产配置可使用 `prepare-production.py --originals PRIVATE_JSON --output NEW_ENV_FILE` 从原始 Secret 生成 0600 文件；缺失发布凭据会明确列出，不生成替代值或自动轮换。`check-services.mjs` 仅检查邮件/GitHub 可达性，不发送邮件或触发发布；实际送达与发布仍须独立验收。

## 构建、部署与恢复

新工作流 **Prepare or publish accepted ECS version** 只允许 main 发起，要求指定 SHA 是 main 的祖先，且精确提交最新 `CI result` 成功。staging 完成完整后端/网站/浏览器验证并生成文件摘要清单；production 消费成功 staging 的同一压缩包，不重新构建，要求所有者确认并经过 production Environment 审批。

工作流使用独立、仅能访问目标实例的 RAM 身份，配置 `ALIYUN_WORKBENCH_ACCESS_KEY_ID`、`ALIYUN_WORKBENCH_ACCESS_KEY_SECRET`。本机用于初始化的凭据不自动上传 GitHub。首次由操作者安装 `/opt/myleafy/install-release.sh`、受保护 env、数据和 Caddy/systemd 配置；备案确认后才建立 `/etc/myleafy/filing-approved`。后续工作流不会创建该标记或修改权威 DNS。

部署按环境使用 flock 串行锁，核验归档 SHA-256、拒绝不安全 tar 路径、校验产物每个文件及源码 SHA，安装锁定生产依赖，然后备份、停服务、迁移、切换 current 和启动。`/health` 与网站 `/release.json` 标记同一源码。失败不自动回退数据库；先检查日志和备份，只有旧代码兼容当前数据库时才恢复上一 current 链接。

部署报告在 `/opt/myleafy/<environment>/deployment.json`，包含源码、上一产物、校验与健康结果，不包含 Secret。恢复数据库时先停写，把故障状态另存，再恢复到新目录并逐表/逐对象校验；服务读写开关独立决定。

## 下载备份

先通过 Workbench 只列出 `/var/backups/myleafy/<environment>` 的已完成 `.tar`，下载所选 tar 和同名 `.sha256`，在 Mac 校验后保存。归档只含加密内容，密钥单独保存。

```sh
workbench download /var/backups/myleafy/staging/SNAPSHOT.tar /LOCAL_PRIVATE_DIRECTORY/ -i i-2ze251tg6q9u5s25jkq4 -r cn-beijing
workbench download /var/backups/myleafy/staging/SNAPSHOT.tar.sha256 /LOCAL_PRIVATE_DIRECTORY/ -i i-2ze251tg6q9u5s25jkq4 -r cn-beijing
```

Workbench 单文件传输上限按所安装版本核对。快照超过限制须分卷并分别校验；不跳过文件，也不以数据库成功代替文件成功。

## DNS 记录准备

先从 Cloudflare 导出 BIND zone 文件，在受保护的本机目录保存。安装 `backend/scripts/ecs/requirements.txt` 后，运行 `aliyun-dns.py --source EXPORT_FILE --plan NEW_PLAN_FILE`，只生成计划，不改 DNS。它保留邮件/TXT/CAA 等记录，替换已知服务域名为 ECS 地址；发现未映射 Cloudflare 子域或不支持类型时停止。阿里云已有冲突记录也停止，不覆盖他人修改。

备案及所有者验收后才使用 `--plan PLAN_FILE --apply --filing-approved`。脚本核对计划以来 DNS 未被修改，只新增已审阅记录，并保存创建结果；部分失败必须根据实际结果重新生成计划，不能盲目重放。NS 与 DNSSEC/DS 另行核对；2026-10-26 公共委派已经是 dns27/dns28.hichina.com，未检测到 DS，不能因为本机旧缓存再次改回 Cloudflare。

## 正式切换验收

备案系统的主体、人脸、短信核验和最终生产验收由所有者完成。切换前核对全部 DNS 记录、CAA、DNSSEC/DS、API/Pages/R2 域名绑定与 HTTPS 证书。切换后分别从权威 NS 和公共解析器检查根域、www、API、下载及测试域，确认不再指向 Cloudflare；验证网站、管理拒绝、签名媒体、WebSocket、邮件及 GitHub 发行流程。对外拨测不得包含真实学生凭据或修改生产业务数据。

旧 Cloudflare 资源先冻结保留，至少 7 天；退役包括 Pages/Workers/D1/R2、旧 Cron、域名绑定与专用发布凭据。旧 Supabase 不在退役范围。未完成的步骤必须继续记为待办，不能凭本地测试或源码合入宣称迁移完成。
