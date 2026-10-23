# 启动、身份、存储与同步全量审查

逐文件完整阅读 App（Theme 由平台组负责）、Core、LoginView、根组 Shared 模型及相关测试；配置/资源采用结构与引用核验。内容 SHA、调用链及状态见 `ios-audit-root.tsv`，总覆盖率以 `ios-ponytail-files.tsv` 为准。没有执行本地 XCTest 或启动 Simulator。

| 编号 | 触发场景与代码证据 | 最小修复及回归 |
| --- | --- | --- |
| R01 | `AppSessionResetter` 批量删除中途失败或先取消通知/清空目录，会遗失无关编辑、仍在使用的文件或提醒。 | `deleteLocalRecords` 统一预取本次模型与文件，先持久清理意图，使用 `LocalModelSave` 局部撤销，提交后清文件及通知。清理失败独立警告。`AppPersistenceAuditTests` 覆盖保存失败与文件重试。 |
| R02 | 账号 A 远端删除 await 后用户已切换 B，旧完成路径继续清 B 数据。 | `AppAccountDeletionCoordinator` 捕获 scopeKey，远端成功后复验才执行本地清理；回归断言 B 清理闭包未调用。 |
| R03 | 社区图片重复缩小以满足字节上限，元数据仍报告初始尺寸；外部 UIImage 入口同样发生。 | 两条压缩策略分别保留，分别使用实际编码 JPEG 尺寸；`ImageRefactorTests` 用极小 maxBytes 触发缩小并对照文件头。方向测试改用非对称像素，避免 PNG 编码字节差异误报。 |
| R04 | iCloud 重复文件引用使唯一键构造崩溃；数据库合并失败却已改 journal；附件未齐时的新本地编辑未被采集，迟到云端覆盖。 | 同内容引用去重、不一致拒绝；单记录模型提交失败还原 journal，冲突 ID 稳定可重放；当前已提交内容等于传入值时不让旧 pending journal 重传过期文本。合并前只采集传入键的最新已提交值，不把缺失附件误判删除。远端课表/格子范围校验后再替换。`ICloudSyncInfrastructureTests` 覆盖重复、保存故障、等待附件期间编辑、非法范围、删除与重放。真实 CloudKit 另验收。 |
| R05 | 语言变化重排提醒、社区 badge 恢复、CloudKit 删除等 await 跨身份或被替代后仍写当前状态。 | 原 scope/generation 在返回后校验；旧通知、busy/error 与 journal 不影响新身份。保留系统已开始事务无法撤销的边界。 |
| R06 | Demo seed/restore 全局 rollback、损坏/部分备份当空、恢复重新生成 Course/Grade UUID 与课程来源学期。 | 严格整体备份读取、局部撤销；成功提交后才清备份/切换标记；原 UUID/sourceSemesterID/updatedAt 保留。缺标识的非空旧备份明确失败且保留，不猜测恢复。`AppPersistenceAuditTests` 覆盖失败、损坏/部分备份与成功恢复身份。 |
| R07 | Login 验证码/登录/注册回调在切校园、切入口、离页或进入 Demo/guest 后更新旧 UI 或凭据。 | 页面持有请求 ID，入口变更使旧结果失效，学校任务取消；自定义认证捕获身份和表单快照，写状态/凭据前复验。真实学校及账号注册另验收。 |
| R08 | `FitnessTestRecordFormatter` 对 NaN/Infinity/巨大数执行 Int 转换导致崩溃。 | 非有限或不可表示值显示现有占位，舍入后用精确 Int 转换；Discover 组 `FitnessTestShareTests` 覆盖各种单位与分钟进位。 |
| R09 | 清理队列只检查相同 ownerID，另一记录引用相同文件时可能删掉 live 文件。 | `LocalFileCleanup` 按同类记录全部 localFilename 检查；Career 文档接入同一队列。回归覆盖不同 UUID 共享文件、同 UUID 替换及最后引用删除。 |
| R10 | Widget 天气原请求永久缺少配置；主 App 已有带观测时间的身份缓存。 | 复用缓存向 archive 写可选天气与原 observedAt，天气成功通知刷新 archive；未认证不发布天气。平台组负责 6h 过期、数字校验、兼容旧 archive 和 timeline。 |
| R11 | 主 App/扩展使用 App Group defaults、文件日期和磁盘容量，却缺相应 required-reason 声明；扩展没有独立 manifest。 | 主 App 补 UserDefaults 1C8F.1、FileTimestamp C617.1、DiskSpace E174.1；Share 独立声明相同实际用途；Widget 仅声明实际 UserDefaults 用途。依据 [Apple 官方说明](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)，plist 结构检查并核对构建产物；App Store 校验另属发布流程。 |
| R12 | 默认工程 `Item` 模型已不在 schema 且全仓无类型调用。 | 完整读取与生产/测试/配置引用检查后删除；泛型参数同名不视为引用。未按文件长度拆分或删除实际功能。 |
| R13 | 根 README 仍描述旧五 Tab 和按学年浏览，与当前三 Tab、固定容器及可选 iCloud 不符。 | 全文核对后修正 iOS 产品说明，保持当前 state 与实际导航一致；未改 Android 或后台说明。 |
| R14 | 远程 Xcode 26.6 对 App 根视图整条修饰链类型检查超时，本地 Xcode 27 编译不能证明受支持工具链通过。 | 在同一 App 内把展示/弹窗、生命周期和通知/环境分别表达为私有 opaque View 属性；保留原修饰顺序、状态归属及全部回调。这针对真实编译故障，不按文件长度拆 View、不引入 AnyView。构建验证，不增加镜像测试。 |

## 配置、资源与本地化

- 工程 target、FSS 编译成员、共享目录、Scheme、SPM 锁文件和 CI 路径匹配已核对。最低 iOS 17；无新增依赖或 schema，Android/后端/Web 实现未改。
- 六个字符串目录检查 JSON 重复键、格式占位符和英中条目；新增错误与取消按钮补翻译，About 改为与主动开启 iCloud 现状一致的说明。
- 全部 asset/icon JSON 引用、SVG XML 与位图可解码/尺寸已核对；工程现有资源全部保留。结构检查不代表最终视觉或 VoiceOver 验收。
- 本地静态与编译、远程离线测试、真实学校/CloudKit/跨进程扩展/权限投递/性能测量分别记录于总报告。不以未采样代码修改宣称性能比例。
