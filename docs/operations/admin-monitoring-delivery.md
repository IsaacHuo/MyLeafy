# Admin 与服务器监控交付

2026-11-04 初次交付，跟踪 #65。当次运行源码 `7e092f09ca64fa9d8cb836c03d982b818794818b`。

## Android 版本入口修复（2026-11-07）

[#77](https://github.com/IsaacHuo/MyLeafy/issues/77) / [PR #78](https://github.com/IsaacHuo/MyLeafy/pull/78)：业务菜单遗漏独立 Android 版本页，现已补回入口。原路由、查看/发布权限、API、数据库和 APK 均保持。新增从总览点击导航的回归覆盖三种角色、移动抽屉、选中状态、刷新/直达和权限拒绝；旧代码可准确复现缺失，发行请求只使用模拟接口。本地类型、生产构建、74 项单元及 33 项相关 Chromium/WebKit/iPad WebKit 用例通过。

[完整 staging 42336454110](https://github.com/IsaacHuo/MyLeafy/actions/runs/42336454110) 与经所有者批准的 [production 42337279249](https://github.com/IsaacHuo/MyLeafy/actions/runs/42337279249) 均成功。两环境运行 `831ab3f15f6af89d1805538b9a9c4dac04ac3526`，生产消费同一 staging 产物；生产 deployment.json 完成于 2026-11-07T04:13:46.168Z，归档、文件、迁移和健康身份校验通过。

生产官网 `/release.json` 与 API `/health` 提交一致，业务、监控和 Caddy 服务 active，部署文件中已包含新菜单。原 Android 1.2.9/code 13 发布元数据前后完全一致，APK SHA-256 仍为 `e61ea941af14641292ca3ad63ace8110f7632f0f026191b95b3bad916ec7ec41`；一次单字节 Range 请求为 206，不扩大为本轮重新校验完整 APK。所有者确认「菜单和版本列表都正常」，完成实际账号验收。

## 初次交付运行与验证（2026-11-04）

/admin 已使用 Refine 5 / Ant Design 5。原 82 项管理动作及六项新监控读取保留在契约内；原认证、CSRF、角色、学校范围、业务数据库与 App 协议保持。未构建或发布移动端。

- 后端 118 项、迁移 13 项、ECS Python 辅助 12 项通过；网站单元 74 项、Chromium/WebKit/iPad WebKit 78 项通过。
- staging 完成 API 故障、备份失败、五分钟恢复、采集器中断/重启续读、请求去重和数据库完整性验证。
- 30 分钟官网/健康/更新只读负载：7,126 个 200；P95 约 2.395 ms，原基线 2.530 ms；监控峰值约 208 MiB、整机平均 CPU 约 0.29%。当时为单环境 worker，不能扩大为全部业务查询和数据规模的证明。
- 后续生产任务诊断暴露逐行相关聚合阻塞。已改为一次聚合关联，并补充 10,000 条离线回归及约 11 万条 staging 历史的真实接口检查：诊断 282 ms，并发健康最大 223 ms。测试数据已清理。[根因与边界](../../logs/2026-11-04-admin-diagnostics-query-block.md)。
- 所有者确认测试邮件三封实收、后台登录/用户管理/监控正常，并在修复后再次确认诊断与社区正常。

Prometheus、node_exporter、两个独立 monitor 与 API/Caddy 正常运行，监控端口全部回环。访问文件及 HTTP 运行错误在落盘前去掉请求路径/查询、头和自由错误文本；固定路由、请求 ID、掩码 IP 保留。真实 staging 故障请求验证敏感标记未写入日志。

## 实际发布

[完整 staging 41837627173](https://github.com/IsaacHuo/MyLeafy/actions/runs/41837627173) 成功。[production 41840198192](https://github.com/IsaacHuo/MyLeafy/actions/runs/41840198192) 获所有者批准，但 runner 向阿里云 OSS 中转上传超时，运行结果保持 failure。随后经本机 Workbench 传输同一归档并通过同一安装器完成发布；实际 deployment.json 为 success，完成于 2026-11-04T14:02:15.568Z。不把人工发布成功写成 GitHub 运行成功。

- 相同归档 SHA-256：`f5c0c3876030d8288ae2a7ead7168c464a2f2b622b10041bde9539cb7c2d5c8c`。
- 网关常规配置 SHA-256：`0294e7093e3d6ad2f561c41cc04849ba078714a7d32a0afd6d86f14219d2cd2d`。
- 安装器完成归档、文件、迁移与健康身份校验；业务库保留，临时后台维护规则已解除。

未来传输失败后，只可在所有者批准的范围内复用相同已验收归档与摘要，继续经过安装器的串行锁和幂等校验。新包装器在输出前脱敏会话/签名参数，仅对已识别的传输故障有限重试。

## 邮件与备份边界

固定收件地址在受保护配置中。三封测试由 Resend 返回 delivered，所有者确认实收。production 发信已启用，staging 正常发信关闭。systemd 每天北京时间 21:00 生成日报；首份在 2026-11-04 21:00 生成，约 21:16 在故障恢复后发送，明确标记统计不完整。异常、恢复和发送账本持久化；监控每日最多十封，为日报保留一封，不升级套餐。

原生云通知仅匹配本实例严重/警告及状态变化，联系人验证和事件接入授权由所有者完成。已通过 ECS 官方模拟事件 SystemFailure.Reboot 验证独立云端通知，明确设置 TriggerRealOps=false，所有者确认收到阿里云模拟告警，实例保持 Running。没有执行真实 VM 停机或重启；不承诺检测所有公网链路故障。

[Configuration/myleafy-ecs](https://github.com/IsaacHuo/Configuration/tree/main/myleafy-ecs) 保存去凭据配置、保留策略、连接和恢复说明。按要求清理本机旧服务器备份、迁移副本及旧构建缓存，保留源码、测试结果、服务器数据、自动快照和密钥。本机不另行下载服务器数据备份；新电脑先按连接提示词只读接入，后续备份由所有者另行安排。
