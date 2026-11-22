# 北林本科教务连接器 v1

原 API 主机的 HTTPS `/v1/academic` 路径。连接器为独立、无数据库的进程，凭据及操作仅在内存存活，不使用社区登录 Cookie 或社区 Bearer。

## 操作生命周期

1. `POST /v1/academic/operations`，JSON 为 `campus: "bjfu"`、`portal: "undergraduate"`、`vpnAccount`、`vpnPassword`，可选 `cookies` 字符串字典。密码不裁剪；账号去除首尾空白。`cookies` 为当前身份和 VPN 路径的教务会话副本，不包含学校 VPN 的 `TWFID`。
2. 201 返回 `operationID`、`operationToken`、ISO 8601 `expiresAt`、整数 `idleTimeoutSeconds`。后续请求使用 `Authorization: Bearer <operationToken>`。首次教务登录无需已有社区账号。
3. `POST /v1/academic/operations/{operationID}/requests`，JSON 为 `method: "GET" | "POST"`、学校原始路径与查询字符串 `path`、可选的 POST `bodyBase64` 和原学校地址 `referer`。可选 `cookies` 字典在这次请求前替换教务 Cookie（包括空字典重置），让现有验证码/登录流程保持候选会话一致；它不能包含 `TWFID`。不接受任意 URL、主机、代理或调用方 Cookie/Authorization 头。
4. 200 返回原学校 `status`、还原为 `http://newjwxt.bjfu.edu.cn` 的最终 `url`、`contentType`、原始字节 `bodyBase64` 及完整 `cookies` 字典。该 200 只表示传输完成，客户端仍需检查学校状态、认证内容、来源学期和解析结果。`cookies` 替换当前 VPN 会话分桶，不能覆盖直连分桶。
5. 成功、失败和取消后都调用 `DELETE /v1/academic/operations/{operationID}`。204 代表学校明确确认退出；`vpn_logout_unconfirmed` 表示本地已释放但学校退出未确认，客户端须独立提示，不撤回已经有效保存的数据。404/410 代表本地操作已不存在，不能重用令牌。

初始仅允许本科登录、验证码、会话验证及课表页面。其他本科功能在课表验收后增加允许资源，不向任意 `/jsxsd` 或任意网页透传。所有跳转都重新检查原学校目标和资源；响应字节不修改，不在连接器重写课程模型。

两分钟无请求或最长五分钟后释放。单个操作的学校请求串行，不同操作各自持有 Cookie。重复用户动作在客户端合并，同一 VPN 账号已有操作时服务端返回 busy；退出尚未完成时也不启动替代会话。初始最多两个并行操作，超量返回 busy，无后台 VPN 会话或队列。

## 失败与客户端行为

错误沿用 `{ "errorEnvelope": { "code", "message", "retryable" }, "request_id" }`。不得把网关原始错误、响应页、Cookie 或表单写入日志/错误报告。

| code | 行为 |
| --- | --- |
| `vpn_authentication_rejected` | 检查 VPN 凭据或账号使用状态，不自动重发密码 |
| `vpn_extra_authentication_required` | 当前 VPN 要求额外验证；明确说明并提供校园网直连 |
| `vpn_unavailable` / `vpn_timeout` | 重试、修改设置或本次直连，保留缓存 |
| `academic_operation_busy` / `academic_request_busy` / `academic_service_busy` / `academic_rate_limited` | 等待当前操作或稍后手动重试 |
| `academic_operation_expired` / `academic_operation_not_found` | 新建操作，不能重用旧令牌 |
| `academic_cancelled` | 停止当前操作，丢弃旧响应 |
| `academic_request_denied` / `academic_redirect_denied` / `academic_response_too_large` | 明确报告不支持的资源/响应，不推断为空结果 |
| `vpn_logout_unconfirmed` | 本地操作已释放；单独显示退出未确认 |

手机没有 VPN 配置时直接走原校园网实现；已有配置时默认连接器，不根据 Wi-Fi 名称或连通性探测自动切换。后台预取不新建 VPN 操作。强智 Cookie 是否有效仍由真实学校请求及既有页面验证逻辑决定。
