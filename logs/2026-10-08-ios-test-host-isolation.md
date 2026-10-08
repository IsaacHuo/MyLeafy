# iOS XCTest 宿主启动逻辑隔离

## 症状与根因

单测修改校园身份后，SwiftUI 的真实根界面会切换到 ContentView，触发社区 bootstrap 和通知恢复。测试代码注入的教务服务只隔离该测试调用，不能阻止 App 生命周期中的默认服务启动。Keychain 报错也不能证明没有发出网络请求：后台会话响应可以先返回，随后本机安全存储才失败。

只在后台协调器或校园身份通知处检查 XCTest 环境不够。测试宿主必须在根 WindowGroup 选择空界面，生产页面的 onAppear、task、scenePhase 和通知订阅都不能挂载；App init 的清理、探针和后台注册也要隔离。SceneBuilder 不支持此处的条件场景分支，条件应置于 WindowGroup 的 ViewBuilder 中。

## 排查与约束

- 检查共享 Scheme 的 TestAction 环境变量，并核对生成 xctestrun 中的宿主 EnvironmentVariables。
- Scheme 不继承生产 LaunchAction 环境；使用明确的 LEAFY_UNIT_TESTING=1，CI/工具重用测试产品时也传入该标记。
- 检查日志是否出现 ContentView startup、community bootstrap 等生产路径，而非只检查 XCTest 断言。
- 默认正式后台组合根和学校传输在单测中直接拒绝请求；HTTP 契约测试使用显式注入的客户端和 URLProtocol，业务测试使用既有服务协议的替身。
- 日期测试的日历时区须与被测日期字符串的解析时区一致。UTC fixture 与按 TimeZone.current 解析的学期/校历混用，会在非 UTC 环境发生前一天偏移和假期周数变化。

未经核查不能声称服务端没有新增匿名会话；发现真实初始化路径时先停止测试、保留日志，再修复宿主隔离。
