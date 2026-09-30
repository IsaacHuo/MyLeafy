# Android 核心体验与 iOS 对比

评审日期：2026-09-30。完成第二轮体验实现与模拟器收尾；参照当前主线 iOS 的文案、业务规则及页面结构。用户指定模拟器优先，小米真机延后。

## 当前结果

综素初始化闪退、校园返回分类丢失、培养方案误取课程编号已修复。首次教务同步、固定课表左轴与月份、课程详情备注/提醒、圆形导航选中底和日迹加号、等宽场馆卡片已实现。医疗与评价直接展开，安卓“周末去哪”及专属代码删除。

保留已登录模拟器及其数据；v7→v8 为增量升级。独立模拟器承担会写入/清理测试数据的自动化验证，未清除用户账号，也未操作小米手机。本轮没有新增 Cloudflare API 或写入生产后台。

## 与当前 iOS 的比较

iOS 依据主线源码与既有设计；Android 依据实际模拟器交互和 Compose 图片。没有同期 iOS 录像或 Release 帧时测量，因此不评分、不编造 FPS，也不宣称两端已经同等流畅。

| 维度 | 当前 iOS 参照 | Android 当前完成度 | 剩余差距与下一步 |
|---|---|---|---|
| 登录与首次使用 | 身份恢复、学校认证及数据获取连贯 | 北林/免登录同页；启动先恢复身份；身份作用域顺序同步课表、成绩、考试，按学期去重，重新认证续传 | 已有账号续传已核对；全新账号首次启动和真实网络异常仍需完整闭环 |
| 课表交互流畅度 | 固定背景、连续日期切换、复用投影 | 唯一背景和固定左轴在 Pager 外；13 节对齐，翻周与快速反向操作通过；预计算教学周内容 | 目前为 Debug 模拟器行为验收；需 Release/profileable 帧时与同期 iOS 对照 |
| 课表美观与阅读 | 月份/时间轴明确，课程信息分配合理 | 月份补齐，周标题箭头移除；保留选周/回本周；课名与教室优先 | 照片对比度、密集冲突课程与 TalkBack 仍需更完整检查 |
| 课程详情 | 完整课次上下文、备注、提醒、教师入口 | 可滚动 Sheet；实际课次进度、时间地点、教师/周次；课程/课次备注、提醒、未保存确认、待关联记录入口 | 本地流程与权限拒绝/重新排期已测；系统实际通知投递、重启恢复尚未完整验收 |
| 成绩呈现 | 紧凑摘要、学期明细、分析图表 | 学期折叠与独立分析页；官方 GPA/平均分和估算区分，课程编号规则沿用 iOS | 基础条形图清楚，但趋势/分布图的视觉细节仍比 iOS 简单 |
| 教学与培养 | 学分要求、类别和课程明细分层 | 明确列与合并单元格解析；真实总学分 167 已核对；明细统一列宽、表头及横向滚动 | 超长正文的阅读密度和横向表格可继续细化 |
| 空闲教室 | 条件与结果绑定、按时间语义查询 | 默认当前周/当天，紧凑选择，楼宇分组；真实查询返回 76 间；改条件立即撤下旧结果 | 保留学校现有全天第 1–12 节范围，不扩展查询协议 |
| 校园与返回 | 分类稳定，工具各自负责 | 固定导航挂载位置；子页返回保留分类；医疗/评价直接嵌入；场馆等宽 | 页面进入/返回通过；远程评价详情和写入仍受 staging 验收限制 |
| 底栏与日迹美观 | 选中态清晰，新增入口明确 | 窄屏图标圆形底，文字在圆外；日迹 56dp 圆形加号；宽屏保留原生 Rail | 6 张根壳基线逐张审阅；真机字体、键盘和系统栏延后 |
| Cloudflare | 主线新版 API、身份与媒体契约 | Android 无 Supabase SDK/运行回退；认证、社区、媒体、资料、通知、评价、共享接口已迁移 | 本地契约通过；staging 写入尚未验收，不等同于已可发布 |

## 验收记录

### 工程与交互

- 完整 JVM 共 149 项：142 通过、7 项外部探测跳过；Debug 构建通过。lint 无错误，104 条 warning、3 条 hint，未宣称零警告。
- 隔离 API 36 模拟器完整一轮 32 项：31 通过，1 项测试未滚动到屏外学院选项。修正测试定位后，学院单项复跑通过；另行使用顶部返回按钮遍历校园工具的测试通过。未把分批复跑称为一次 32 项全绿。
- 迁移检查保留 v7 课程、随记与日程；备注/提醒按身份和学期隔离；失败保存回滚、刷新关联、首次同步去重/部分失败/认证暂停、固定左轴和背景、通知路由拒绝错误身份均有回归。
- 提醒覆盖权限拒绝时保存但未启用、授权后排期、重复协调不重复创建、身份切换取消；通知路由通过 Activity intent 验证。尚未以系统真实通知点击、关机重启或厂商省电限制验证完整投递。
- 综素全部 16 个学院规则可进入，包含待补齐规则。已有草稿使用原有本机状态；未以用户真实草稿逐条核验。
- 6 张根导航基线逐张审阅后验证通过；窄屏圆形选中底正常，200% 标签可读；600/840dp 原生 Rail 维持原样。录图成功本身不算审阅通过。
- 最新 10 张合成布局图片覆盖登录、成绩、分析、校园的 360/600/840dp、浅深色、100%/130%/200% 组合；本轮重新审阅校园 3 张，其他组合沿用既有评审，不宣称每个页面的完整组合覆盖。
- 固定时间轴/背景翻周短录屏及静态位置断言已生成，不能据此推导两端帧率。

### 已登录账号的学校读取

| 项目 | 结果 |
|---|---|
| 本机升级与保留 | v8，31 条课程、92 条成绩保留，未清除/卸载用户安装 |
| 首次队列续传 | 用户重新认证后继续；现有副本 bootstrap，当前学期可信空考试记录为完成；重启不重复全量同步 |
| 成绩与官方排名 | 刷新完成；官方 GPA 2.65、加权平均 79.62；本机 92 条成绩 |
| 培养方案 | 实际刷新后总学分 167；通识选修 8.5、通识必修 43、专业基础 55.5、专业核心 15、本专业选修 7、集中性实践 15、毕业论文 14、拓展教育 9；脱敏表尾样本纳入回归 |
| 空闲教室 | 第 4 周/周三全天查询返回 76 间，楼宇分组；改为周四后旧结果即时撤下 |
| 教学计划 | 与培养方案按独立内容结构识别、保存；合并列对齐经过解析回归，未逐条核对所有课程与官网 |

真实读取核对不替代全新账号首次启动、实际断网、保存失败等全部场景的现场测试；相关异常行为以本地回归为当前依据。

### 校园入口清单

| 分类 | 进入与返回检查 | 业务边界 |
|---|---|---|
| 学校教学 | 成绩、考试、教学与培养、校历/作息、综素、荣誉均通过顶部返回回归 | 真实核对见上；荣誉写入使用测试数据，不修改用户记录 |
| 自习安排 | 空闲教室进入/返回通过 | 当前周/当天查询及改条件撤下结果通过；座位预约为现有外链，外部提交未测 |
| 体育相关 | 阳光长跑、体测、场馆开放进入/返回通过，切 Tab 后分类保留 | 场馆卡片等宽；本机编辑依原有行为，未提交学校预约 |
| 医疗事项 | 分类直接展开，原有内容可达 | 复用原医疗状态与台账，无新增线上报销操作 |
| 评价相关 | 分类直接展开，原有筛选可达 | 搜索过期响应受请求代次隔离；staging 远程详情与写入未完整验收 |
| 周末去哪 | 安卓分类、路由和专用实现删除 | iOS 未改 |

### Gradle 检查的问题与答案

以下为本轮托管检查的原问题及结果；失败定位后仅复跑相关范围。

| 原问题 | 答案 |
|---|---|
| “Does the first stability, navigation, fixed-axis and sync implementation compile with non-destructive Room v8 migration?” | 初次失败：日迹 FAB 缺 import；已修正，后续编译通过。 |
| “Do course notes, exact reminder scheduling, notification routing and embedded campus pages compile?” | 通过。 |
| “Do initialization, curriculum parsing, first-sync scope and course reminder calculation regressions pass?” | 初次测试编译失败：组件新参数改变位置调用；修正参数位置。 |
| “Do first-sync, parsing, reminder and refresh association regressions pass after API corrections?” | Sheet 缺实验 API opt-in；修正后复跑。 |
| “Do first-sync, parsing, reminder and refresh association regressions pass with the sheet opt-in fixed?” | 通过。 |
| “Do the Android app and isolated-device regression APKs build after second-round changes?” | 通过。 |
| “On the isolated emulator, do preserved Room migration, all-campus return navigation, fixed-axis paging and course personal flows pass?” | 12 项中 11 通过，月份合并语义断言失败；修正断言。 |
| “Do fixed-axis paging and notification-to-course navigation pass after correcting month semantics?” | 测试代码访问 protected 回调及缺 import，修正测试。 |
| “Do fixed-axis paging and course-notification routing pass using a real Activity intent?” | 轴子项语义和路由失败；分开定位。 |
| “Do axis bounds and reminder routing pass after accounting for merged semantics and ActivityScenario lifecycle?” | 固定轴通过；路由仍失败。 |
| “Does course-notification routing pass while restoring ActivityScenario launcher identity for teardown?” | 路由超时；页面使用旧 Room 投影，修正为读取已提交课程。 |
| “Does reminder navigation read committed course data and preserve its selected week and identity boundary?” | 通过。 |
| “Do the full JVM regressions, Android lint and debug assembly pass including the deidentified real-school footer fixture?” | 通过；149 项、142 通过、7 跳过，lint 数量见上。 |
| “Does the complete isolated-emulator interaction suite pass including all college rules and latest visual layouts?” | 32 项中 31 通过；屏外学院选项未先滚动，修正定位。 |
| “Can all college rules render when the test scrolls the lazy selector before looking up each offscreen option?” | 通过。 |
| “Can the six changed navigation-shell screenshots be recorded for individual review?” | 录图通过，随后逐张审阅。 |
| “Do the six individually reviewed updated navigation baselines verify?” | 通过。 |
| “Does every campus tool return through the toolbar to its original category?” | 通过。 |

## 下一步计划

1. **发布前可靠性**：隔离后台恢复后，验证资料清空、图片发布重试、通知已读、评价与共享权限；补全干净学校账号首次启动、实际断网和会话失效恢复。改动保存在任务分支，暂不并入可发布主线，不打 release tag。
2. **课前提醒系统闭环**：验证系统真实投递/点击、重启、权限撤销、时间调整；用户恢复真机验收时再检查小米省电与字体。未授权时继续明确显示未启用。
3. **视觉收敛**：优先成绩趋势/分布、培养方案长表格、复杂课次详情与照片对比度，不增加业务模块。
4. **流畅度与无障碍**：以同样数据在 Android Release/profileable 与 iOS 测量启动、连续反向翻周和长列表；再实测 TalkBack、200% 字号、键盘与触控命中。目前不能宣称已达到 iOS 同等流畅度。

截图和录屏仅保留最新批次，位于 `android/app/build/emulator-latest/`；版本控制回归基线在 `android/app/src/test/screenshots/`。账号备份与测试产物均在 ignored build 目录，不提交学号、凭据或真实教务 HTML。
