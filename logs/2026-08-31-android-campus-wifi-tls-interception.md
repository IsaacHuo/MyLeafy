# Android 社区在校园 Wi-Fi 下发生 TLS 主机名不匹配

> 历史记录：现场为 Xiaomi 24069RA21C、Android 16、MyLeafy Android 1.0.0。当前产品状态以 `state/` 为准。

## 现象

- 学校账号登录成功后，社区首次加载失败。
- 客户端请求 `pjefjlnohqrqsseajpdu.supabase.co`，TLS 校验收到的证书却是 `CN=*.bjfu.edu.cn`，证书 SAN 仅包含 `*.bjfu.edu.cn` 和 `bjfu.edu.cn`。
- Android 正确拒绝该连接，并报告 hostname not verified。

## 调查

- 手机未设置系统 HTTP 代理，也未设置 Private DNS。
- 手机 DNS 将 Supabase 域名解析到 Cloudflare 地址 `172.64.149.246`，与宿主机解析结果一致，因此不是简单的错误 DNS 记录。
- 失败时手机连接 `bjfu-wifi`；切换到另一条网络后，不改账号、不改客户端、不改 Supabase，社区 Feed 立即正常加载。

## 根因

`bjfu-wifi` 的传输路径对目标 HTTPS 连接返回了北京林业大学域名证书。该证书不属于 Supabase 域名，标准 TLS 主机名校验必须拒绝连接。

这不是 Supabase Auth、RLS、匿名登录或社区仓储逻辑失败。不能通过信任全部证书、关闭 hostname verification 或加入校园证书例外来绕过，否则社区会话和用户数据可能被中间人读取。

## 修复

- 用户侧：切换到不拦截该连接的网络，或关闭会接管流量的代理/VPN 后重试。
- Android 1.0.1：将此类证书主机名不匹配映射为可操作的网络提示，不再把底层证书详情直接展示给用户；TLS 校验保持不变。

## 验证

- 同一台真机切换网络并点击重试后，社区分类、帖子列表和根导航正常显示。
- JVM 回归测试覆盖包装异常中的 `SSLPeerUnverifiedException`，确认用户提示不包含证书或 Supabase 域名详情。

## 剩余问题

- 校园网络策略不由客户端控制；如果后续其他外部 HTTPS 服务出现同类问题，应先比对目标域名、实际证书、DNS 结果和所用网络，再判断是否为同一根因。
