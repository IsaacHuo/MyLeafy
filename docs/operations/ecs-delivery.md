# ECS 交付与迁移操作

设计、数据门槛与边界见 [迁移说明](../engineering/aliyun-ecs-migration.md)。2026-11-02 已完成生产切换，来源与验收以 CURRENT 和实际部署报告为准。

## 当前生产交付

最新 Admin/监控版本及实际发布、邮件和恢复边界见 [交付记录](admin-monitoring-delivery.md)。以下初次迁移结果是历史证据；本机旧数据备份已按所有者要求清理，不将历史下载记录视为当前可恢复副本。

初次迁移运行提交 `f544392b7ded8fd0b3fe59fadedeaf949c6994a5`，成功 staging [41319033640](https://github.com/IsaacHuo/MyLeafy/actions/runs/41319033640)、所有者批准的 production [41323260270](https://github.com/IsaacHuo/MyLeafy/actions/runs/41323260270)。七个服务域名直连 `8.141.82.15`，HTTPS 校验通过，原业务/发行控制策略已恢复。所有者确认现有 App 和网站正常；原 code 12 APK 5,860,825 字节完整下载及 Range/哈希验证通过，未重建或签名。

迁移后生产备份 SHA-256 `323e08b85890b75dfba57eb6394832df62cb20fa9f22b40f4af4808d96e6812a` 已下载至 Mac 并恢复校验 71 表、499 对象。本机长期恢复包位于 `~/MyLeafy-Server-Backups/2026-11-02/`，密钥独立保存在受保护位置。可移植配置与换机手册见 [Configuration/myleafy-ecs](https://github.com/IsaacHuo/Configuration/tree/main/myleafy-ecs)。

## 目录与配置

- `/opt/myleafy/<environment>/releases/<commit>`：构建产物；`current` 原子链接。
- `/var/lib/myleafy/<environment>`：SQLite、私有 files、公开 releases、维护标记和恢复报告。
- `/etc/myleafy/<environment>.env`：0600 运行配置，保留原生产认证与媒体签名 Secret；测试和生产独立。
- `/etc/myleafy/<environment>.backup.env`：0600，仅包含 BACKUP_ENCRYPTION_KEY；密钥在服务器之外单独保留。
- `/var/backups/myleafy/<environment>`：加密快照 tar 及同名 SHA-256；只保留最近 1 天，归档通过校验后不再保留解包目录（恢复时先解包再运行 restore）；备份不是公开网站文件。

bootstrap 只安装 Node 24.22.1、Caddy 2.11.7、系统用户和目录；不启动公网入口，不覆盖已存在配置。Node 使用 SHA-256，Caddy 官方清单使用 SHA-512，失败即停止。私有 Caddy 配置只监听 127.0.0.1:8081，另保存为 `/etc/myleafy/Caddyfile.private`。公开配置须备案后启用，继续导入该私有入口用于后续受控验收；公开 staging 启用时将其 SITE_ORIGIN 改为 https://staging.myleafy.space。www 跳转主域，下载域名继续服务原 APK。

北京 ECS 实测 Node 默认地址族连接尝试会过早放弃可达的邮件端点；受保护环境配置使用 `NODE_OPTIONS=--network-family-autoselection-attempt-timeout=2000`，运行参数样例保持一致。该设置不固定远端 IP、不关闭证书验证，也不自动重发邮件。2026-11-01 同步新 publisher token 时通过标准输入更新仓库 Secret，服务器值与本机待上线配置一致；候选与正式 APK 均未重建或重签名。

Caddy 的出站 ACME HTTP/2 曾连续等待响应超时；当前 systemd 设置 `GODEBUG=http2client=0`，仅调整出站客户端协议，入站 HTTPS/HTTP2 与证书验证保留。七个证书实际签发并通过公网校验，自动续期使用同一参数。[Go 参数说明](https://pkg.go.dev/net/http)

## 数据操作（仓库根目录）

使用 Node 24。凭据从受保护 env 文件载入；现有 Wrangler OAuth 时可将旧 CLOUDFLARE_API_TOKEN 留空。所有目标目录必须是新目录。

```sh
node --env-file=backend/.env.migration backend/scripts/ecs/inventory.mjs production
node --env-file=backend/.env.migration backend/scripts/ecs/export.mjs staging PRIVATE_BACKUP --rehearsal
node --env-file=backend/.env.migration backend/dist/restore.mjs PRIVATE_BACKUP EMPTY_DATA_DIRECTORY --rehearsal
```

restore 默认保留 `maintenance`，失败保留 `restore-failed`，不激活残缺数据。完成逐表/文件校验后，先做备份恢复演练，再由操作者接通私有验收。待应用 migration 单独执行 `node backend/scripts/ecs/migrate.mjs DATABASE_PATH`，须先停服务和备份。该工具保留 `d1_migrations` 记录，不能对已建结构重放全部历史 SQL。

最终生产导出只在备案和验收均满足后执行：使用 `freeze-source.mjs` 和独立 `backend/cutover/maintenance.ts` 冻结现有 Worker 的全部入口，保存报告并确认在途任务结束，通过 `SOURCE_FREEZE_REPORT` 指定报告，以 `--quiesced` 导出，再 `--production` 恢复。冻结工具会阻断普通表的全部写入；不完整报告不能用于最终快照。目标先核对原始快照，再删除专用冻结机制，默认仍处于 maintenance。若目标从未开放写入，先停目标，再显式执行 `recover-source.mjs FREEZE_REPORT --confirmed-no-target-writes` 恢复源冻结机制与记录的旧代码；DNS 恢复另行处理。目标已接收新写入时禁止直接执行此恢复。不要为导出在源库删除 FTS 表。备份中原始运行配置可用同一备份密钥及 AAD `ecs-runtime-env-v1` 解密，不能把解密结果写入报告。

若文件传输中断，可在原 `--quiesced` 命令末尾加 `--resume`。工具重新核对同一源冻结、结构和已完成表的摘要，并认证缓存文件后继续；非一致演练、已完成快照、旧冻结或损坏检查点均拒绝续传。对象读取覆盖响应正文的断线重试，检查点原子替换；未记录完整元数据的文件重新读取并与已有密文核对，不覆盖不同字节。续传完成前不能导入生产。

生产配置可使用 `prepare-production.py --originals PRIVATE_JSON --output NEW_ENV_FILE` 从原始 Secret 生成 0600 文件；缺失发布凭据会明确列出，不擅自轮换。所有者已确认新的发布共享密钥，保存在待上线配置中；正式切换时从该同一份配置通过标准输入更新 GitHub 的 `MYLEAFY_RELEASE_PUBLISH_TOKEN`，并在 ECS 激活对应 `RELEASE_PUBLISH_TOKEN`，确认两端一致后再允许发布。`check-services.mjs` 只执行供应商只读检查，不发送邮件或触发发布；实际送达与发布仍须独立验收。

备案期间可使用待上线配置做只读供应商验收。加 `--candidate-database` 时，从指定演练库只读选择最新候选，核对私有草稿及源码/文件身份，完整下载 APK 并按库内原始大小与 SHA-256 校验；仅流式计算，不重新签名、不发布。任何供应商或内容检查失败均返回非零退出码；报告不包含 Token、临时下载 URL 或学生资料。

```sh
cd /opt/myleafy/staging/current/backend
/usr/local/bin/node --env-file=/etc/myleafy/production.env.pending scripts/ecs/check-services.mjs \
  --candidate-database /var/lib/myleafy/production-rehearsal-20261026/database.sqlite
```

此项通过只说明供应商权限、下载字节和发信域名状态满足检查；不代表邮件已送达、发行已获批准或生产已上线。北京 ECS 的 GitHub 候选下载实测曾超过 60 秒，管理下载与验收工具采用有上限的五分钟窗口；不改变 APK 或客户端协议。

## 构建、部署与恢复

新工作流 **Prepare or publish accepted ECS version** 只允许 main 发起，要求指定 SHA 是 main 的祖先，且精确提交最新 `CI result` 成功。staging 完成完整后端/网站/浏览器验证并生成文件摘要清单；production 消费成功 staging 的同一压缩包，不重新构建，要求所有者确认并经过 production Environment 审批。

工作流使用独立、仅能访问目标实例的 RAM 身份，配置 `ALIYUN_WORKBENCH_ACCESS_KEY_ID`、`ALIYUN_WORKBENCH_ACCESS_KEY_SECRET`。本机用于初始化的凭据不上传 GitHub。独立 CI 身份可通过 `provision-ci.py --directory PRIVATE_DIRECTORY` 生成权限计划，核对后加 `--apply` 创建并配置 staging/production Secrets；远程执行限定目标 ECS，不创建控制台登录密码。新 AccessKey 首次生效可能短暂延迟，工具只对该明确错误做有限重试，不扩大权限。首次由操作者安装 `/opt/myleafy/install-release.sh`、受保护 env、数据和 Caddy/systemd 配置；备案确认后才建立 `/etc/myleafy/filing-approved`。后续工作流不会创建该标记或修改权威 DNS。

部署按环境使用 flock 串行锁，核验归档 SHA-256、拒绝不安全 tar 路径、校验产物每个文件及源码 SHA，安装锁定生产依赖，然后备份、停服务、迁移、切换 current 和启动。`/health` 与网站 `/release.json` 标记同一源码。失败不自动回退数据库；先检查日志和备份，只有旧代码兼容当前数据库时才恢复上一 current 链接。

部署报告在 `/opt/myleafy/<environment>/deployment.json`，包含源码、上一产物、校验与健康结果，不包含 Secret。恢复数据库时先停写，把故障状态另存，再恢复到新目录并逐表/逐对象校验；服务读写开关独立决定。

## Admin、指标、日志和邮件

配置与恢复入口见 [Admin 监控](../engineering/admin-monitoring.md) 和 [Configuration 监控手册](https://github.com/IsaacHuo/Configuration/blob/main/myleafy-ecs/MONITORING.md)。先部署已验收的业务产物，再启动对应环境 monitor；production 继续消费同一 staging 归档并由所有者批准。

首次安装由操作者运行 `backend/deploy/install-monitoring.sh`，通过受保护进程环境提供固定收件人。脚本只安装官方校验过的 Prometheus / node_exporter，生成 per-environment MONITOR_TOKEN 和最小 monitor env；原 API 的认证、媒体和发行配置保持。`/etc/myleafy/{environment}.monitor.env` 为 root 0600，不提交真实值。正常 staging 邮件保持关闭。

Caddy 生产配置启用前先 validate，再 reload；新服务器必须同时修改 probe map 中旧公网/私网地址。访问记录在落盘前删掉 URI、查询和头，IP 掩码，路由只记固定模板。公开入口不暴露 9090/9100/3120/3121/3140/3141。Caddy 管理仍为回环 2019。保留现有 ACME 网络 drop-in。

监控独立于业务 API 和数据库，可单独停用或恢复。指标保留 14 天、整体磁盘目标 1 GiB；两环境访问日志与索引合计目标 512 MiB，每库硬限 100 MiB 并预先清理，原始文件按 16 MiB / 七份旧文件 / 七天轮转。日报、告警、发送账本三十天。容量、缺失和采集中断在后台可见；请求数不等于活跃用户。

生产邮件验收使用受控 CLI `dist/monitor.mjs --test-notifications <accepted-commit>`，通过 systemd 载入受保护 env 并以 myleafy-monitor 身份运行，避免 root 创建 SQLite 文件。该命令只发送三封明确标记的测试邮件，并以源码去重，不制造真实生产故障。实际到达收件箱由所有者确认；服务商接受不是最终送达。

正式启用时只将 production.monitor.env 的 MONITOR_EMAIL_ENABLED 改为 true，重启 monitor@production 并确认 report timer。日报每天北京时间 21:00 生成，重启最多补最近一期，首日明确标记统计不完整。监控每日最多十封，为日报保留一封，启用前核对 Resend 的实际额度，不升级套餐。验证码仍由原 API 发送。

备份/部署通过 root 写入有限期维护标记和备份结果；monitor 只读这些回执，不接触业务数据库或解密密钥。停用监控时保留历史目录，不恢复旧业务库。正常回退仍需要核对代码与现有数据库的兼容性。

## 下载备份

先通过 Workbench 只列出 `/var/backups/myleafy/<environment>` 的已完成 `.tar`，下载所选 tar 和同名 `.sha256`，在 Mac 校验后保存。归档只含加密内容，密钥单独保存。

```sh
workbench download /var/backups/myleafy/staging/SNAPSHOT.tar /LOCAL_PRIVATE_DIRECTORY/ -i i-2ze251tg6q9u5s25jkq4 -r cn-beijing
workbench download /var/backups/myleafy/staging/SNAPSHOT.tar.sha256 /LOCAL_PRIVATE_DIRECTORY/ -i i-2ze251tg6q9u5s25jkq4 -r cn-beijing
```

服务器只保留最近 1 天的 `.tar`，解包目录在归档校验后即删除；恢复时先 `tar -xf SNAPSHOT.tar -C PRIVATE_BACKUP`，再按上文 restore 命令做演练或正式恢复。

Workbench 单文件传输上限按所安装版本核对。快照超过限制须分卷并分别校验；不跳过文件，也不以数据库成功代替文件成功。

## DNS 记录准备

先从 Cloudflare 导出 BIND zone 文件，在受保护的本机目录保存。安装 `backend/scripts/ecs/requirements.txt` 后，运行 `aliyun-dns.py --source EXPORT_FILE --plan NEW_PLAN_FILE`，只生成计划，不改 DNS。它保留邮件/TXT/CAA 等记录，替换已知服务域名为 ECS 地址；发现未映射 Cloudflare 子域或不支持类型时停止。阿里云已有冲突记录也停止，不覆盖他人修改。

备案及所有者验收后才使用 `--plan PLAN_FILE --apply --filing-approved`。脚本核对计划以来 DNS 未被修改，只新增已审阅记录，并保存创建结果；部分失败必须根据实际结果重新生成计划，不能盲目重放。初次切换的 19 条计划曾按原值保留邮件记录；2026-11-02 支持邮箱另行迁至阿里邮箱，当前 DNS 共 18 条。旧导入计划不能重放，最新邮件记录以 [Configuration DNS 快照](https://github.com/IsaacHuo/Configuration/blob/main/myleafy-ecs/dns/records.json) 为准。NS 与 DNSSEC/DS 另行核对；2026-10-26 公共委派已经是 dns27/dns28.hichina.com，未检测到 DS，不能因为本机旧缓存再次改回 Cloudflare。

## 正式切换验收

备案系统的主体、人脸、短信核验和最终生产验收由所有者完成。切换前核对全部 DNS 记录、CAA、DNSSEC/DS、API/Pages/R2 域名绑定与 HTTPS 证书。切换后分别从权威 NS 和公共解析器检查根域、www、API、下载及测试域，确认不再指向 Cloudflare；验证网站、管理拒绝、签名媒体、WebSocket、邮件及 GitHub 发行流程。对外拨测不得包含真实学生凭据或修改生产业务数据。

旧 Cloudflare 后端资源先冻结保留，至少 7 天；退役包括 Pages/Workers/D1/R2、旧 Cron、网站/API/下载绑定与专用发布凭据。支持邮箱已迁至阿里邮箱免费版，所有者实测收信和回复成功；Cloudflare Email Routing 已关闭，阿里云 DNS 的旧 Cloudflare MX、SPF 授权与 DKIM 已移除。当前根域 MX 为 mx1/2/3.qiye.aliyun.com（优先级 5/10/15），SPF 为 `v=spf1 include:spf.qiye.aliyun.com -all`。Resend 和历史 DirectMail 子域记录保留，不将 `mail` 的现有记录替换为 CNAME；邮箱登录 [qiye.aliyun.com](https://qiye.aliyun.com/)。换 ECS 只更换业务 A 记录，邮箱为独立产品，不包含在 ECS 数据备份中。旧 Cloudflare Zone 随退役另行核对，不能影响其他域名或全局收件目标。旧 Supabase 不在退役范围。未完成的步骤必须继续记为待办，不能凭本地测试或源码合入宣称迁移完成。
