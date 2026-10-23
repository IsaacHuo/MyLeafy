# Community / Schedule / Cloudflare 完整阅读结果

本组完整阅读 79 个 Swift 文件（含从 root 转交的共享社区模型、CampusRefactorTests、RefactorTestSupport、BackendClientTests 和新增 SessionScopeTests），逐文件最终 SHA-256、职责、调用与测试证据在 `ios-audit-community.tsv`。原始内容和修改后的全部差异均已阅读；测试文件核对的是生产行为，不以检索命中冒充阅读。

核对本机个人数据和实际有界媒体/分页负载，使用总报告中的 P01–P25、A01–A25 编号。没有新增依赖、存储 schema 或通用框架；full 级别保留当前功能和视觉。P18 本组没有新增临时捷径，P23 的设备与性能校准尚未执行。

| 编号 | 具体触发、根因与后果 | 已实施最小修复 | 回归与验证边界 |
| --- | --- | --- | --- |
| C01 | 注销、切换校园/身份或 detach 时，先前成功 HTTP/profile/email/bootstrap 响应仍可能被调用方采用；bootstrap 旧任务 defer 还可清掉新任务 | BackendClient 在请求前后复核 token、会话代次与 CampusOperationScope；SessionManager 为 restore/编辑/邮箱/校园变更复核作用域与 detach 代次，bootstrap 用独立请求 ID；gate 和多步媒体/共享课表操作跨 await 复验 | 新增 logout 后成功响应拒绝、detach 后 restore/email 不回填、bootstrap 中切换身份不授权；真实登录/网络/共享课表仍待设备验收 |
| C02 | abort 失败被 try? 吞掉后立即 cancelled 并删除本地媒体；进程终止留下 cancelling 后又没有恢复入口；旧上传 worker 的结束清理可能移除新取消 worker | 取消意图继续持久化；仅当前 owner 执行 abort，失败保留 cancelling、错误和媒体；启动/网络恢复重试；用 worker ID 保护结束清理；远端已 published 按真实发布成功处理；任务行提供重试取消 | 新增失败 abort 保留文件及 restarting 后完成取消；原 200 次进度不写盘、检查点/身份测试保留；真实后台 URLSession 进程恢复需设备验收 |
| C03 | publish handoff 删除草稿失败后，composer 清理所有附件 URL，包含仍属于草稿的附件；repository 的 try? decode 又允许直接覆盖损坏 manifest | 清理只允许 composer 暂存目录直属文件；现存 manifest 解码失败立即抛出，保留原数据 | 新增 staging ownership 与损坏 manifest 保存拒绝；既有 enqueue 失败保留草稿/owner 隔离测试保留 |
| C04 | 菜品建议的 canSubmit 错把不可见的教师字段设为必填，导致永远不能提交；课程/菜品第一页被星级筛选成空时隐藏翻页，后页匹配项无法到达 | 仅课程要求教师名；空的本地筛选结果保留已有 load-more 控件和分页逻辑 | 按实际分支与 repository 输入静态核对；这些简单 UI 可达性修复未增加镜像测试，交互验收待设备 |
| C05 | 多次照片选择、保存或身份切换与 loadTransferable/压缩交错时，旧结果可能回填已保存/新选择的草稿 | 社区与随记 composer/editor 使用局部请求 ID 和作用域，保存/移除/离开使旧结果失效；随记整批照片读取失败保留原草稿并显示错误；停止语音后保存前再次复验原作用域 | 结构与完整调用链复读、静态解析；Photos/iCloud 媒体授权与极快选择交互待设备；未宣称已测性能收益 |
| C06 | 语音识别或相机正在等待授权时关闭页面，迟到授权仍能启动麦克风/摄像头；旧识别回调只在实际 start 后才有 token | 语音 start 在权限前建立 session ID，每次权限/音频激活返回后复验；stop 立即失效；相机用线程安全活动标志阻止已关闭 session 配置及照片回调 | 新增两项异步权限停止回归，均在麦克风启动前结束；真实相机、音频中断与设备权限 UI 待验收 |
| C07 | 旧分页与新的相同 query refresh 并行时，query 相等不足以阻止旧页覆盖刷新；banner/detail/poll/notification 重叠请求也存在迟到回写或取消清空新状态 | 复用局部 load ID 和 CampusOperationScope；同 query refresh 可使旧分页失效；通知 mute 使旧加载失效，取消/跨身份错误不覆盖新状态 | 新增同 query 分页迟到和 banner 请求替代回归；既有 query 变更、投票部分失败、badge subscription ID 回归保留 |
| C08 | 社区 Mock 入口、样本/卡片、placeholder 与旧 Supabase RPC DTO/first-value helper 已无生产调用，仍与当前 REST 模型并存 | 全仓核对源代码、测试、配置、脚本与 backend/supabase 引用后移除无入口 Mock 组和旧 wire DTO；实际 profile null/权限与评论点赞严格解码保障迁移到当前 REST ProfilePatch 和 CommunityCommentLikeState；随记三类无引用的目录级 deleteAllFiles 删除，账户清理测试改为当前 deleteLocalRecords 事务入口与隔离清理队列 | 保留当前功能测试；新增 REST patch null vs omission/不得携带校园权限字段，点赞单对象/缺字段拒绝测试；历史后端 SQL 和后端实现未修改 |

## 既有四项修复复核

- 随记四类保存继续通过 `ScheduleMemoPersistence` / `LocalModelSave`，失败只恢复本次字段和媒体；永久删除经过 `LocalFileCleanup` 的持久意图与 live-row 检查。五项持久化回归完整阅读。
- 上传字节进度仍只改内存，路径/状态转换落盘；本轮继续修复其取消链路，不移除检查点或 owner/authority 保护。
- 图片 loader 接收不可变 URL/id/revision，在 detached 任务加载后检查取消/作用域/run ID；新加窄的 sources 初始化供荣誉/医疗复用，不把 SwiftData 模型传到后台。压缩背景色与质量保持各自策略。
- 教务后台解析入口属于 root/timetable 组，本文不重复宣称其验证。

## 实施与验收记录

本组完成 `swiftc -frontend -parse` 静态语法检查及差异检查，没有运行构建、XCTest、Simulator、真实后台或正式发布。集中 `build-for-testing`、精确提交 CI 和设备证据由 root 总报告记录，不能从本组“read/fixed”状态推导运行通过。

媒体 file importer/Photos、CloudKit、本地语音/相机权限、后台 URLSession 进程恢复、Safari/QuickLook/系统分享、VoiceOver 和帧时/耗电/峰值内存仍是运行验收边界。没有以同步函数名、try?、文件长度或相似 UI 包装本身判定缺陷；不同压缩策略、语义组件和具备测试注入价值的协议保留。

`ScheduleMemoAdvancedEditorViews.swift` 任务开始前已有删除 `.onDisappear { imageLoader.reset() }` 的未提交改动已保留，本组没有恢复该行或将其当作审计成果。
