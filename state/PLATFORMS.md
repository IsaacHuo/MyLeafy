# 双端功能、验证与交付状态

核对日期：2026-10-24。实现基于本次整合的当前源码，包含 iOS Ponytail 全仓审计、Android 对齐、历史待合修复和双端规范化。源码准备版本为 iOS 3.2.6 / build 1、Android 1.2.6 / code 10；不代表已发行。2026-10-23 的全量整合只做静态检查；2026-10-24 的 iOS 设备编译、完整远程 CI 及后续集成证据集中在 [PR #46](https://github.com/IsaacHuo/MyLeafy/pull/46)。历史单分支结果与最终组合分开。

## 如何读取

- **实现**：已合入表示主线有实际工作路径；部分实现、未实现与不适用分别标注，不代表测试或发行完成。
- **验证**：以下源码/测试链接证明实现与用例存在。历史执行结果引用 CURRENT 和具体设计验收记录，不能当成本轮运行。自动化、设备、真实学校会话分开。
- **交付**：正式版本、build/code、源码与分发证据统一在[发布索引](../docs/operations/release-notes.md)，本表不复制版本号。iOS 最新商店版本的完整功能/源码对应关系待核实；Android 逐项功能是否随正式版本交付，需对应 Release/source 核对。
- **差异**：需要对齐、平台特有、刻意保留、待产品决定是不同状态。只为边界明确的后续工作建立 Issue，不因缺少对应入口就自动承诺补齐。

## 主要能力

| 能力 | iOS 实现与源码 | Android 实现与源码 | 差异与后续 |
|---|---|---|---|
| 登录、免登录与教务恢复 | 已合入；[Auth](../leafy/Features/Auth/)、[学校会话](../leafy/Services/SchoolAuthenticationService.swift)，含本科/研究生及本地入口边界 | 已合入；[Auth](../android/app/src/main/java/com/myleafy/android/features/auth/)、[初始同步](../android/app/src/main/java/com/myleafy/android/features/campus/InitialAcademicSync.kt)，本科与免登录 | 刻意保留登录范围差异；学校真实会话各端独立验收 |
| 根导航与校园能力 | 已合入；[App](../leafy/App/)、[Campus](../leafy/Core/Campus/)，三 Tab + 校园左栏 | 已合入；[navigation](../android/app/src/main/java/com/myleafy/android/navigation/)，三 Tab + 校园领域入口 | 已对齐；社区/日迹在校园内，Android 保留原生返回与自适应导航 |
| 课表、个人日程、备注/提醒与背景 | 已合入；[Timetable](../leafy/Features/Timetable/)、[Schedule](../leafy/Features/Schedule/)，固定 20 周容器与独立个人数据 | 已合入；[timetable](../android/app/src/main/java/com/myleafy/android/features/timetable/)，原生网格、背景、关联备注与 AlarmManager 提醒 | 新版 iOS 个人数据/课表容器规则与 Android 关联处理有差异；是否对齐待产品决定，本轮不迁移数据 |
| 成绩、考试、教学/培养与空教室 | 已合入；[Parsers](../leafy/Parsers/)、[AcademicTools](../leafy/Features/Discover/Presentation/AcademicTools/) | 已合入；[parsers](../android/app/src/main/java/com/myleafy/android/parsers/)、[campus](../android/app/src/main/java/com/myleafy/android/features/campus/) | 共享学校 fixtures 与数据语义；页面范围及失败保留缓存分别验证 |
| 日迹、随记/个人日程与统计 | 已合入；[Schedule](../leafy/Features/Schedule/)，含媒体、回收站和本机统计 | 已合入；[schedule](../android/app/src/main/java/com/myleafy/android/features/schedule/)，含标签、统计、回顾、回收站与导出 | 核心能力已存在，编辑器/媒体细节非完全等同；iOS 文件职责整理见 [#39](https://github.com/IsaacHuo/MyLeafy/issues/39) |
| 社区、媒体、评论、评价与通知 | 已合入；[Community](../leafy/Features/Community/)，持久化发布队列及权限边界 | 已合入；[community](../android/app/src/main/java/com/myleafy/android/features/community/)、[Cloudflare services](../android/app/src/main/java/com/myleafy/android/services/cloudflare/) | 共用后端契约，媒体上传与通知端到端验收不能由 DTO 测试替代 |
| 共享课表 | 已合入；[Profile](../leafy/Features/Profile/)、[Cloudflare service](../leafy/Services/Cloudflare/)；发布者日期/作息新字段已接入源码 | 已合入；[sharing](../android/app/src/main/java/com/myleafy/android/features/timetable/sharing/) | iOS `calendar_config` 与 D1 0015 的生产交付以 CURRENT 既有待部署记录为准；Android 同等展示待产品决定 |
| 系统通知、导出与外部导入 | 已合入；[App coordinators](../leafy/App/)、[Share Extension](../LeafyShareExtension/)、[外部导入共享](../LeafyExternalImportShared/) | 部分实现；[ICS 导出](../android/app/src/main/java/com/myleafy/android/features/timetable/export/)、[日迹通知](../android/app/src/main/java/com/myleafy/android/features/schedule/notifications/) 及课程提醒已实现；没有 iOS 同款分享扩展 | 系统特有交互保留；Android 实际通知投递/重启恢复仍需设备验收 |
| 课表 Widget | 小/中/大号视觉升级，iOS 27+ 竖向超大号；[leafyWidget](../leafyWidget/)、[共享快照](../LeafyWidgetShared/)，验证边界见 [设计与证据](../docs/design/ios-widget-visual-upgrade.md) | 未实现；当前主线未见 AppWidget provider / receiver | 平台功能缺口；是否建设 Android Widget 待产品决定，无默认交付承诺 |
| 个人数据云同步 | 已合入；[Core/Sync](../leafy/Core/Sync/) 的 CKSyncEngine，默认关闭，主动开启 | 未实现个人数据云同步；[同步中心](../android/app/src/main/java/com/myleafy/android/features/profile/ProfileSyncScreen.kt) 是学校数据刷新，不代表云同步 | iCloud 为平台特有；生产 schema / 双设备待 [#36](https://github.com/IsaacHuo/MyLeafy/issues/36)，跨端云同步待产品决定 |
| 长尾校园工具 | 已合入；[Discover](../leafy/Features/Discover/) | 已合入选定范围；[campus](../android/app/src/main/java/com/myleafy/android/features/campus/) | 学习空间、职业规划、考研等不迁移 Android，按 ARCHITECTURE §11 的既有取舍，不创建虚假对齐任务 |

## iOS iPhone Duo 自适应补充（2026-10-24）

仅 iOS 新增基于窗口尺寸的课表、社区窄列、评分筛选、日迹输入及分享扩展调整，沿用三 Tab 与校园左栏；Android 与共享契约未改，不产生新的双端对齐承诺。iOS CI 使用 Xcode 27.1 / iOS 27.1 SDK，最低目标仍为 iOS 17。本轮以本地构建通过为交付边界，静态检查/编译结果见 CURRENT；原独立任务未触发远端 CI，现与小组件升级累计整合于 PR #46；整合期间不重复本地 XCTest 或操作 Simulator，Duo 折叠、分屏、键盘和真机视觉仍待 [#44](https://github.com/IsaacHuo/MyLeafy/issues/44) 验收。没有 TestFlight/App Store 发布结论。

## iOS CI 检查边界补充（2026-10-24）

九项失败的审核区分实际实现问题与过细的显示解码断言：保存恢复和 CSV 数据检查保留并修复实现，图片继续检查尺寸、方向与内容，不要求八位通道逐点舍入差最多 2。未跳过用例或修改必需 CI result。原因见 [排查记录](../logs/2026-10-24-ios27-ci-failure-audit.md)，完整累计提交的远程结果及集成状态见 PR #46；本地未启动 Simulator，真机与发行仍待各自验收。

## 快速迭代验证与交付（2026-10-24）

日常只自动运行受影响平台的格式、项目配置、类型/契约与基础安全检查；完整编译、XCTest、Android 设备/截图、浏览器及数据库测试只手动运行 Full validation（平台/all）。Android 候选与 staging 也仅手动，staging 保留完整后端/网站前置验证，生产审批及同产物发布继续保留。基础 CI 与完整验证分开报告，现有用例未删除。基线 60113cf 已通过完整 CI（774 通过、1 跳过）；之后变更的静态/增量编译证据见 PR #46，不扩大为新增完整运行或真机验收。

## 验证证据与保留边界

| 范围 | iOS | Android |
|---|---|---|
| 自动化用例 | [leafyTests](../leafyTests/) 含 AcademicReliability、CampusNavigation、TimetablePersonalSync、ScheduleMemo、ICloudSyncInfrastructure、社区队列等；测试存在不等于本轮执行通过 | [JVM / Roborazzi](../android/app/src/test/) 与 [原生设备测试](../android/app/src/androidTest/) 含解析、作用域 Room、共享、通知规划、导航及背景生命周期 |
| 历史执行 | [CURRENT](CURRENT.md) 保留各任务独立结果及中断记录；最近 iCloud 修复只完成签名/构建，实际同步未完成验收 | [课表背景记录](../docs/design/android-timetable-backdrop.md) 保留 76 项截图、175 JVM 通过/7 跳过及设备范围；[核心审查](../docs/design/android-core-review.md) 记录隔离后台与系统投递边界 |
| 本轮工程验证 | 规范化独立分支曾通过最低目标构建和 XCTest（659 通过、1 跳过），且 199 个格式化文件的字符串解析值一致；2026-10-23 含 Ponytail 的整合只做静态检查；2026-10-24 的累计提交验证与 CI 修复以 PR #46 精确提交为准 | 独立分支的构建/JVM/Lint/截图及设备结果分别见相关报告；本次对完整整合源码执行格式化，未重跑 Android 构建或测试，不将历史成功扩大为最终组合通过 |
| 发布前人工验收 | 真实学校会话、真机 UI/系统日历、iCloud 生产与双设备；[iOS 发行锚点 #38](https://github.com/IsaacHuo/MyLeafy/issues/38) 待补 | 正式包覆盖升级及候选验收见 [#37](https://github.com/IsaacHuo/MyLeafy/issues/37)；实际系统通知/后台共享与媒体仍需独立核验 |

本轮工具与流程追踪于 [#35](https://github.com/IsaacHuo/MyLeafy/issues/35)，不把本轮验证扩展成生产发布结论。候选、正式版与本次源码分别管理。
