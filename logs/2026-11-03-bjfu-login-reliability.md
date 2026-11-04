# 北林教务登录可靠性排查与修复

日期：2026-11-03。跟踪 [#67](https://github.com/IsaacHuo/MyLeafy/issues/67)。仅使用公开登录页和合成数据，不使用真实学生凭据。

## 根因与边界

学校公开登录页在独立红字区域展示“本平台为互联网非涉密平台，严禁处理、传输国家秘密、工作秘密及敏感信息。”，它不是密码失败原因。双端过去将任意红色 font 内容当登录错误；alert/showMsg 只匹配第一项，遇到内置校验即停止该类查找，因此后续真实错误会被公告替代。公开页面并不能证明用户描述的学校网页首次失败/再次成功的原因；该现象仍需失败当次学校响应，未在本轮归因。

iOS 还存在无效密钥编码为空仍提交、验证码刷新清理登录中的 Cookie、旧任务更新当前状态，以及 Swift Character 与 JavaScript UTF-16 单元不一致的问题。普通英文符号的 1,224 组合成离线对照未出现编码/解码丢失，不能将反馈一概归为符号转义错误。

## 当前修复

- 双端跳过精确的固定公告（容忍排版空白），遍历全部候选，保留真实错误及其他安全提示。
- 无效密钥、学校 HTTP 异常和未知认证结果明确失败；不提交空 encoded，不把未知错误当验证码拒绝反复发送密码。首次验证码加载保留学校登录服务的具体异常提示，不将有效 HTTP 响应中的密钥异常统一改报为网络不可达。
- 会话验证必须有明确的认证页面内容；公告和学生首页地址均不能单独确认登录。真实拒绝不被原有会话状态掩盖。
- iOS 认证操作互斥并绑定会话代次，取消、切门户和界面关闭使旧请求失效；旧响应及 defer 不影响替代操作。首次登录和手工恢复均取消所属任务。
- iOS 交错编码按 UTF-16；浏览器表单会将交错产生的未配对代理单元替换为 U+FFFD，双端一致处理。该行为与学校网页一致，不承诺学校自身支持任意 Unicode 密码。密码不裁剪、不规范化。
- 研究生密码加密协议与现有本科自动恢复次数限制保持原语义；没有新增后台协议或凭据存储格式。

## 回归样本

`contracts/jwxt/fixtures/login_messages.json` 为合成页面，包含公告、内置校验后的真实 alert、第二项红字、锁定、无关安全错误、空页及未知页。

`login_encoding.json` 包含 1,224 组普通字符组合和 11 组空格/组合字符/emoji/控制字符及代理单元边界用例。预期由学校公开登录页 onSubmint 的 substring 交错循环在 Node 中离线生成，再经 URLSearchParams 的浏览器表单 USVString 转换；所有账号、密码和密钥均为合成数据。Swift 按 UTF-16 数组比较，避免 String 的规范等价比较掩盖差异。

iOS 显式注入隔离 request loader 和凭据保存器，逐项检查保存参数及仅在会话验证后保存；默认传输仍禁止单测真实联网，正式构造默认使用原 Keychain 保存实现。凭据缓存失败不撤销已确认的登录，系统 Keychain 读写单独在设备验收。Android 沿用 MockWebServer。回归覆盖请求体、Cookie、成功/真实拒绝/未知响应、异常密钥不发登录请求、取消及替代请求互斥。

## 验证证据

- Android：`spotlessApply spotlessCheck`、Debug APK 构建与五个相关 JVM 测试类全部通过，32 项通过、0 失败/跳过。1,235 组编码向量由一个参数化循环用例逐项检查，不计为 1,235 项独立测试。
- 仓库：12 项 CI 选择/汇总规则回归、分层检查、任务 Swift 格式与 diff 检查通过。
- iOS：初版在任务专用 DerivedData 中串行执行 iOS 17 最低目标 build-for-testing，通过并生成新测试 bundle。随后既有模拟器报告 Data Migration Failed，未执行用例；新建隔离模拟器仍停在 ContainerMigrator，且主机出现磁盘不足。补充恢复表单重复点击保护后的增量构建在资产编译阶段因磁盘不足中断，不能扩大此前构建结论为最终源码通过。
- 已保留构建/启动日志，并只清理本任务 DerivedData、新建测试设备和任务 worktree 生成的 Android build 目录；未清理其他工作区、既有模拟器或用户数据。最终 iOS 组合源码已通过远程 Full validation，精确提交和结果见下文。
- 基础 CI 按最终精确提交另行核对；未进行真实学校登录、真机交互或发布 App。

### 首次远程全量结果与修正

`3fbd33f` 的基础 CI [41574941121](https://github.com/IsaacHuo/MyLeafy/actions/runs/41574941121) 通过；iOS Full validation [41574942887](https://github.com/IsaacHuo/MyLeafy/actions/runs/41574942887) 构建通过，795 项中 793 通过、1 跳过、1 失败。唯一失败为新增用例直接从 CI Simulator 系统 Keychain 读取保存密码得到 nil；该用例的请求编码、Cookie、成功会话和身份断言均通过。测试结果未提供底层 Keychain 状态码，不能据此断言具体系统权限原因。

将凭据保存与网络一样作为显式注入的测试依赖，检查密码/账号/校园/门户原样传递、真实拒绝或会话验证失败不保存，以及缓存保存失败不回滚有效会话。正式默认仍调用既有 `SchoolLoginCredentialStore.save`，没有放宽登录成功判定或删除原有传输/会话断言。修正后重新对精确提交执行 CI 和 iOS Full validation。

### 登录修复独立验证

- `bf58f2dbdf09882e58f17fd330ce5c2bf76107bf` 的基础 CI [41576709814](https://github.com/IsaacHuo/MyLeafy/actions/runs/41576709814) 通过。
- 同一提交的 iOS Full validation [41576651654](https://github.com/IsaacHuo/MyLeafy/actions/runs/41576651654) 通过：iOS 17 最低目标构建成功，796 项中 795 通过、0 失败、1 项既有跳过；新增的 16 项登录可靠性用例全部通过。没有新增跳过或降低认证断言。
- Android 本地 Debug 构建、32 项定向 JVM 测试、双端格式、分层和 12 项 CI 规则回归通过；1,235 个共享编码向量在双端均逐项验证。
- 首次重放的后端监控改动未影响移动端源码；随后主线新增了 iOS 我的菜单及 Android 分享卡片（`768baea`），因此保留这些改动并重新执行组合源码的 iOS Full validation。登录相关实现、用例和共享 fixtures 与上述已验证版本保持一致，组合结果另行记录。最终精确提交基础 CI 见 [PR #69](https://github.com/IsaacHuo/MyLeafy/pull/69)。
- 状态为 Acceptance：真实学校账号的首次登录、重新登录、自动恢复、设备 Keychain、真机交互及正式 App 发布仍分别待验收。本轮没有使用真实学生凭据或发布 App。

### 与新 iOS 主线组合验证

`692dbe2` 保留 `768baea` 的 iOS 菜单与分享卡片后，基础 CI [41581880923](https://github.com/IsaacHuo/MyLeafy/actions/runs/41581880923) 通过；iOS Full validation [41581882685](https://github.com/IsaacHuo/MyLeafy/actions/runs/41581882685) 构建通过，798 项中 796 通过、1 既有跳过、1 失败。全部登录用例通过，唯一失败是既有 `testCommunityFeedStagesLatestSnapshotUntilUserAppliesIt` 的 `XCTAssertTrue`。

该测试在异步暂存刷新后固定睡眠 100ms 再断言，而刷新经过会话、并发帖子/投票和 actor 调度；社区生产代码及该用例与已通过的独立修复版本完全一致。同文件的合并刷新用例已采用最多 3 秒、每 10ms 检查完成条件的方式。只将失败用例改用相同的有界条件等待，保留暂存、未自动应用、用户应用和缓存的全部断言，不修改社区生产行为或跳过用例。调整后重新验证组合源码。

### 最终组合验证与交付核对（2026-11-04）

- `8b4eafa99981c84cc046ee8963b0c9817081b2a7` 的基础 CI [41583650965](https://github.com/IsaacHuo/MyLeafy/actions/runs/41583650965) 与 iOS Full validation [41583655677](https://github.com/IsaacHuo/MyLeafy/actions/runs/41583655677) 均通过。包含最新 iOS 主线与本轮修复的组合源码已完成 iOS 17 最低目标构建，798 项中 797 通过、0 失败、1 项既有跳过；16 项新增登录用例全部通过。
- 社区暂存刷新用例改为有界条件等待后通过，全部原有业务断言保留；没有修改社区生产代码或新增跳过。
- Android Debug 与 32 项定向 JVM 测试通过；共享 1,235 组编码向量均已在双端逐项验证。后续没有 Android 实现或依赖变化。
- 最后只补充验证文档，移动端实现、测试、共享 fixtures 和构建入口与上述已验证源码一致；最终文档提交的精确基础 CI 以 [PR #69](https://github.com/IsaacHuo/MyLeafy/pull/69) 为准，不重复已通过的编译与测试。
- [#67](https://github.com/IsaacHuo/MyLeafy/issues/67) 保持 Acceptance：仍待真实学校账号首次登录、重新登录、自动恢复、设备 Keychain 及真机交互验收。未使用真实学生凭据自动测试，未发布 App，也未改动学校系统。
