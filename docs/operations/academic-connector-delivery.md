# 北林课表连接器交付

源码和离线验证不代表已部署。范围为 iOS 本科课表及首次登录，Android 与其他教务功能不随本轮改动。跟踪 #79 / #81 / #82，PR #84。

## 指定提交 staging

1. 当前提交通过基础 CI 和相关完整验证，按仓库规则集成 main。运行 **Prepare or publish accepted ECS version**，环境 `staging`，填写该完整 SHA；不重用其他提交的通过结果。
2. 发布包包含 `dist/academic-connector.mjs` 和 `deploy/myleafy-academic@.service`。既有安装器切换到指定产物后启动独立连接器，并要求回环 `3131/health` 的 commit 与 API、站点一致。连接器不读取业务 `.env` 或数据库。
3. **首次启用路由单独核对**：现网 `/etc/myleafy/Caddyfile` 不会因产物中包含模板而自动改变。以该提交的 `backend/deploy/Caddyfile.public` 为参考，仅将 staging API 主机块中的 `/v1/academic`、`/v1/academic/*` 转发到 3131，保留其余 3101 路由、日志脱敏和生产主机块。私有回环入口使用 `Caddyfile.private` 的 academic handler，位于通用 `/v1/*` handler 前。先留存现网配置及摘要，运行 `caddy adapt` / `caddy validate` 后再 graceful reload；不更换宿主机默认路由。
4. 验证新服务只监听回环，运行在独立 DynamicUser、无可写业务目录、无 core dump、禁止 swap 的限制中。生产和 staging 原 API/站点健康检查保持正常。
5. 无真实凭据的 HTTPS 验收：`POST /v1/academic/operations` 的空 JSON 返回 `400 invalid_request`；有 Origin 的请求返回 `403 academic_origin_denied`；无操作令牌的 requests 请求返回 `401 academic_operation_token_required`。这些检查不登录学校，不以原 API 的 404 视为成功。

## iOS 真机验收

- 使用明确指向 staging 的 iOS 构建；主线默认生产 API 的构建不能用来验收未部署的生产连接器。
- 校园网登录后配置 VPN；非校园网首次登录先配置 VPN。确认 VPN 与教务密码分别输入，人工验证码可继续完成。
- 有配置默认 VPN，用当前教务 Cookie 请求课表；学校确认失效后才恢复认证。已有 Cookie 跨服务器出口是否可复用必须据真实结果记录。
- 下拉与缓存页同步只取本次课表；连续触发合并。失败保留旧课表、备注和提醒；成功保存后核对课表与 Widget。
- 手动选择本次校园网直连，确认使用手机会话且下一次恢复 VPN。后台不建立连接；成功、失败、取消和超时释放；学校退出未确认单独提示。
- 未保存凭据用后移除；保存凭据仅此设备 Keychain。退出清理会话，清除全部本地数据同时删除凭据。切换账号后旧响应不能写新账号的缓存。

真实账号只由本人手动输入，不加入自动化样本、环境变量文件、命令行或日志。学校页面、Cookie 和凭据不作为构建/测试附件。

## Production 与发行

staging 验收完成后才请求所有者批准 production，消费同一产物；首次公开 3130 路由按同样方法核对并单独验证。后端部署不代表 iOS 发布，iOS 仍经 Archive → TestFlight / App Store 验收与发行。连接器不写业务数据库，代码恢复与业务数据库恢复继续分开决定，不自动回滚数据库。

## 已取得的证据

2026-11-22：目标 ECS Caddy 2.11.7 对新模板 `adapt`、systemd 255 对独立 unit 的 `verify` 通过；没有 reload、新服务启用或生产变更。后端 134 项单测通过，完整后端运行 [45003204927](https://github.com/IsaacHuo/MyLeafy/actions/runs/45003204927)（`c6344f8`）通过；最终源码与 iOS 验证以 PR #84 的精确提交为准。
