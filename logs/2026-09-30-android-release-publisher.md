# Android 双发行的 draft 查询与上传失败

## 症状与根因

GitHub Actions token 创建 draft 成功后，REST 按 tag 查询以及列表查询可能仍无法得到该 draft，owner 凭据的本地结果不能代表 Actions token。使用 GraphQL `repository.release(tagName).databaseId` 获取已知 ID，之后按 release/asset ID 操作，避免把查询不到解释为“不存在”并重复创建。

Cloudflare 上传曾返回 403；同一接口使用默认 Python User-Agent 得到边缘 1010，明确的 `MyLeafyReleasePublisher/1.0` User-Agent 则进入 Worker 参数校验。这与发行 token 或 APK 签名无关，不能关闭 WAF/TLS 验证或通过输出 token 排查。

正式 universal APK 的多架构文件超过原先自定 64 MiB 上限。限制应兼容实际已签名文件，并保持在服务请求大小限制内；当前发行接口限制为 100,000,000 字节，超限仍拒绝，R2 流式写入并核验 SHA-256。

## 可靠处理

- 创建 draft 后直接使用返回 ID；恢复任务使用 GraphQL 查 ID、REST 按 ID 读取，资产按 asset ID 回读。
- APK 不可变：同版重试只接受相同文件和元数据，不能重建签名包后覆盖已有资产。
- 两边资产回读校验后才公开并登记；登记失败回退新公开的 GitHub draft。响应丢失时通过指定版本及 hash 确认是否已提交，不能误撤回成功发布。
- 发布请求使用明确 User-Agent，错误日志不包含认证 headers 或响应敏感内容。

## 验证与边界

协调器回归覆盖新 draft ID、登记失败回退和响应丢失后确认。实际正式流水线完成 Cloudflare/GitHub 双发布，系统安装器验证同签名覆盖安装。当前部署状态与版本以 `state/CURRENT.md` 为准；这些事实不代表大陆网络速度或全系统版本均已验收。
