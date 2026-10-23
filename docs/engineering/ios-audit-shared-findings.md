# Shared 与补充分组审读

完整阅读 7 个生产文件、6 个已有测试文件和新增 `SharedAuditBoundaryTests.swift`；每个最终文件 SHA-256 与调用/测试证据见 `ios-audit-shared.tsv`。本组不运行本地 XCTest 或 Simulator。

| 编号 | 具体触发和根因 | 最小修复与验证 |
| --- | --- | --- |
| S01 | 调用方已 clear 进度或开始另一轮操作，旧 reporter 仍可通过 record→begin 重新创建遮罩；不属于该操作的 stage 也先切换了 controller 的 kind。 | reporter 捕获本轮 ID，clear/替代后旧回调失效；验证 allowedStages 后才改变 controller。新增旧回调、替代同类型操作和非法 stage 回归。 |
| S02 | 手动重新认证 sheet 用无持有的 Task 读取验证码/提交登录，用户取消退出后任务仍可更新 challenge、显示失败或触发原页面继续操作。 | sheet 持有自己的两项任务，离开时取消并清敏感输入；await 后检查取消；登录期间禁止刷新验证码。既有身份/认证测试保留；真实验证码、权限与手动取消仍须设备验收。 |
| S03 | 后台返回的研招来源 URL 只用 URL(string:) 校验，file/javascript/相对路径可成为非空 URL，继续交给仅接受 HTTP(S) 的系统浏览器。 | 在来源模型边界验证 http/https 与非空 host，失败不提供打开地址。新增有效 HTTP(S) 与危险/缺失 host/相对地址回归。 |
| S04 | Photos 权限请求可能在调用任务取消后才返回，保存入口会继续创建照片资产。 | 取得权限后、开始 Photos 事务前再次检查任务取消；不声称能撤销已交给 Photos 的事务。 |
| S05 | 长期持有的天气服务在初始化时绑定旧校园身份缓存 key；跨身份再次使用会读写旧缓存。Widget 若把读取时间当观测时间，还会延长天气新鲜度。 | 默认 cache 改为每次获取开始时捕获身份，注入 cache 接口保留；保存前在 MainActor 核验 scope，取消不返回旧 fallback；新增成功通知和保留原 savedAt 的 temperature snapshot getter。相关生产修改位于已全文阅读的 Discover/WeatherServicing；3 项天气身份/时间回归加入本组测试。 |

静态语法检查与全文审查不等同构建/执行通过；统一类型检查、iOS 17 编译和远程 CI 结果由根代理记录。未发现需要改变平台兼容 wrappers、滚动观察器或投影测试语义的额外缺陷，不因代码行数或样式偏好重写。
