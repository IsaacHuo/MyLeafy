# Cloudflare 部署完成与 HTTP 节点传播

`wrangler deploy` 返回新 version ID 后，紧接着请求自定义域名的 `/health` 仍可能读到旧 Worker。首次受控 staging 部署中，迁移和部署已经成功，立即核对却收到不含 `commit` 的旧响应；稍后同一域名返回所选提交。响应为 `Cache-Control: no-store`，不能把这种现象当成浏览器缓存，或通过去掉提交校验掩盖。

部署和恢复脚本通过 `waitForDeploymentJSON` 有限等待 Worker `/health` 和 Pages `/release.json`。最多 20 次，每次 HTTP 最长 5 秒，两次之间 3 秒；记录观察到的提交，始终要求最终匹配所选提交。旧提交、暂时的 404/5xx 或连接超时可继续等待；错误环境、权限错误、明确不健康状态立即失败，超出尝试次数也失败。首次 Pages 发布后即时回读曾返回 522，稍后同一网址和部署别名均返回正确版本，不能去掉最终成功核对。数据库恢复不属于这个等待或代码恢复流程。

调查时先区分：Cloudflare 控制面的当前 Worker/Pages ID、HTTP 返回的源码提交、网站实际服务绑定。保留部署报告和 request ID；不要在诊断中输出 API token 或其他 Secret。

另外，固定版本 Wrangler 4.110.0 的 Pages deploy 不支持 `--config` 自定义路径，即使全局帮助包含这个参数。使用 Cloudflare 支持的 [配置重定向](https://developers.cloudflare.com/workers/wrangler/configuration/#generated-wrangler-configuration)：项目 `.wrangler/deploy/config.json` 的 `configPath` 相对该文件定位所选配置，再运行不含 `--config` 的 Pages deploy。网站 build 同时编译 Pages Functions，防止仅有 Vite 构建成功却遗漏函数编译问题。

自动 staging 的变化基线不能只读 Worker `/health.commit`：网站失败时 Worker 已更新，再次运行会误判“无变化”。`stagingBase` 只在 Worker 与网站同属 staging 且源码提交一致时使用该基线；缺少网站版本标识或两者不同则重新准备。错误环境及权限错误仍直接失败。
