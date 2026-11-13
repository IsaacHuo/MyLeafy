# 北林 VPN 接入探针

这些工具用于 #80 的人工接入验证，不是生产连接器，也不加入日常 CI 的真实账号测试。

- `probe-auth.mjs`：一次 VPN 认证、脱敏资源摘要及 POST 退出；输入为一次性 RSA-OAEP 密文。
- `probe-web.mjs`：验证学校自身网页 VPN 能否读取强智首页、密钥和验证码。
- `probe-school-rpc.mjs`：回环、短期、加密 RPC 验证服务，校验教务登录及课表结构；密码错误停止，只有明确的验证码错误允许有限恢复。
- `probe-school-local.mjs`：本机控制器，通过标准输入接收凭据并加密传递，不以明文参数或环境变量传递。
- `probe-captcha.swift`：仅供本机验证使用的 Vision 工具，通过管道处理图片，不保存图片；不代表 iOS/Android 自动识别已经验收。

离线验证：

```sh
node --test backend/tests/academic-vpn-probe.node.mjs
bash scripts/format-swift.sh --check backend/scripts/academic-vpn/probe-captcha.swift
swiftc -O backend/scripts/academic-vpn/probe-captcha.swift -o /tmp/myleafy-vpn-captcha-probe-20261110
```

真实验证需要已配置的 Workbench 与本人授权；先核对固定 ECS 目标与当前部署。通过隐藏输入及子进程 stdin 启动本机控制器，禁止把密码放入 shell 命令、仓库、环境变量或日志。不在 CI 中注入真实学校凭据。

控制器会创建独立的 `/dev/shm/myleafy-school-probe-*` 短期服务。单次最长 135 秒，应用在 115 秒开始取消和退出；回环地址、192 MiB、禁用交换及 core dump。退出后需核对没有遗留探针服务或监听，并只清理本任务的临时源码目录。学校页面、Cookie 和验证码不写到持久文件。

成功退出码只表示脚本定义的真实验收通过；`authenticated` 单独表示 VPN 认证，必须同时检查课表结果与退出状态。来源学期、解析和缓存保护仍须双端验证。证据及边界见 `docs/design/bjfu-academic-vpn-sync.md`。
