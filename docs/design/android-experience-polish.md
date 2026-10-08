# Android 现有功能 UI 与体验打磨

本轮遵循已确认的课表优先计划，参照当前 iOS 的课程内容层级、紧凑分组和辅助信息样式。保留现有入口、五个根 Tab、5/7 天 × 13 节单屏课表，以及 Android 返回、键盘与权限行为。iOS 源码、后端 API、Room v9 和教务计算口径均未改变。

## 展示规则与实现

| 范围 | 本轮落地 | 保留的行为 |
|---|---|---|
| 周次 | 48dp 选择入口与箭头；根据实际文字宽度决定日期同排或另起一行；选周列表定位到选中周，区分本周与正在查看 | Pager 驱动周次，显式选择后继续滑动 |
| 课程 | 统一字号；按实际卡片高度分配课名行数，宽高容许时为地点预留一行；窄卡先去地点；地点去重、清理空白 | 原始数据与完整详情不变，完整课程语义不截断 |
| 网格与时间轴 | 空格填充与描边减弱；轴、网格和时间线共用累计像素边界，包含非整数密度；今日列比课程弱 | 背景与左轴固定，翻周只移动日期和课程 |
| 时间 | 校园时区分钟流，仅 RESUMED 收集；恢复前台立即读时钟；跨午夜同步日期；隐藏周末同步撤下周末时间线 | 不触发网络、学期投影或额外缓存 |
| 课程详情 | 标签随字体宽度增长；教师入口至少 48dp；明确区分备注保存、配置保存、提醒启用与权限阻塞 | 半屏/上拉、编辑展开、IME 避让、保存失败保留草稿、放弃确认 |
| 全端 | 沿用 Leafy Token，辅助正文 12sp/17sp；分组标题使用 titleMedium 与 heading 语义；大字号提示条将操作换行；深色弹层更中性 | 既有设计系统、导航与反馈入口 |
| 校园与考试 | 分类胶囊更轻；成绩与课程名分配宽度；考试时间、地点与编号分层 | 官方值、本地录入和导入校验口径 |
| 成绩分析 | 趋势 Y 轴、轻参考线和点位；等值趋势置中，单点明确不构成趋势；分布零值可读；分类柱图按字号扩宽并横向滑动；删去重复条形明细 | 统计、排名方向与导出数据 |
| 教学与毕业 | 可访问的章节展开行；毕业分类名称、数值在不足宽度时换排 | 既有表格同宽列、横滑、展开恢复及官方/估算/未知区别 |
| 教室、综素 | 教室时间与状态可换排，日期格式错误靠近字段；综素成对分数字段根据宽度与字号改为上下排列，数字键盘 | 结果绑定查询条件、材料与学院记录隔离 |
| 长跑、体测、场馆 | 周期日期与剩余次数分层；体测数值、单位、日期分层，分秒范围就近提示；场馆展开行至少 48dp，长资料按标签/内容分行 | 周期、提醒、数值范围与本地资料 |
| 日迹 | 随记/日程内容卡统一圆角、层级与间距；限制列表摘要高度；长倒计时可换到下一排；统一末项与新增按钮留白 | 分区与滚动恢复、草稿、标签/统计/回顾/回收站 |
| 社区 | 弱化卡片边框与作者/日期，保留标题和内容重点 | 双列封面比例、刷新与分页保留内容、搜索与发布流程 |
| 我的及其他校园页 | 更新说明使用正文，进度使用 liveRegion；登录、设置、荣誉、医疗、评价复用本轮字体、表面、标题与提示条 | 权限、验证码、附件、台账和明确提交 |

极短屏与 200% 字号有实际空间上限：时间轴先去结束时间；若节次与开始时间两行也放不下，则仅展示节次，完整区间仍在朗读与详情中。这比显示半行时间更可辨认。极窄课程只承诺可点击、可朗读和尾部省略，不承诺全部文字可见。

本轮没有重建导航或表单状态，也没有添加新的功能、背景选项、图表库、动画或缓存框架。医疗、荣誉及评价等页主要获得共享组件的改进，没有把未修改的业务流程写成新功能。

## 视觉证据

优化前基准为 `b4a5345f11603197e4f06d10feb1a94d8babe7ed`。先重新运行原有截图验证，再保存 52 张原始基线。固定数据在 `ScreenshotFixtures.kt`，Robolectric API 36、xxhdpi；测试名称标明宽度/字号/主题，未指定时为各测试类的默认配置。

| 对照 | 优化前 | 优化后 |
|---|---|---|
| 课表，360dp/200% | [原图](https://github.com/IsaacHuo/MyLeafy/blob/b4a5345f11603197e4f06d10feb1a94d8babe7ed/android/app/src/test/screenshots/com.myleafy.android.testing.TimetableScreenshotTest.weekdaysFontScale200.png) | [新图](../../android/app/src/test/screenshots/com.myleafy.android.testing.TimetableScreenshotTest.weekdaysFontScale200.png) |
| 课表，短屏/140% | [原图](https://github.com/IsaacHuo/MyLeafy/blob/b4a5345f11603197e4f06d10feb1a94d8babe7ed/android/app/src/test/screenshots/com.myleafy.android.testing.TimetableScreenshotTest.weekdaysSmallHeightFontScale140TimesVisible.png) | [新图](../../android/app/src/test/screenshots/com.myleafy.android.testing.TimetableScreenshotTest.weekdaysSmallHeightFontScale140TimesVisible.png) |
| 成绩分析，600dp/130% | [原图](https://github.com/IsaacHuo/MyLeafy/blob/b4a5345f11603197e4f06d10feb1a94d8babe7ed/android/app/src/test/screenshots/com.myleafy.android.testing.GradeAnalysisScreenshotTest.analysis600Font130.png) | [新图](../../android/app/src/test/screenshots/com.myleafy.android.testing.GradeAnalysisScreenshotTest.analysis600Font130.png) |
| 日迹随记 | [原图](https://github.com/IsaacHuo/MyLeafy/blob/b4a5345f11603197e4f06d10feb1a94d8babe7ed/android/app/src/test/screenshots/com.myleafy.android.testing.RootContentScreenshotTest.scheduleMemosLight.png) | [新图](../../android/app/src/test/screenshots/com.myleafy.android.testing.RootContentScreenshotTest.scheduleMemosLight.png) |
| 社区，200% | [原图](https://github.com/IsaacHuo/MyLeafy/blob/b4a5345f11603197e4f06d10feb1a94d8babe7ed/android/app/src/test/screenshots/com.myleafy.android.testing.CommunityScreenshotTest.contentFontScale200Reachability.png) | [新图](../../android/app/src/test/screenshots/com.myleafy.android.testing.CommunityScreenshotTest.contentFontScale200Reachability.png) |

新增图片覆盖 393dp/130% 明亮图像背景、412dp/200% 深色图像背景、跨月空周横屏、周次日期排版、等值/单点/零值图表、200% 综素字段和展开行。照片对比测试使用确定的明暗位图纹理，不等同于所有用户照片。运行截图与课表短录屏保存在本机 `android/app/build/ui-polish/`，长期基线留在 `src/test/screenshots/`。

## 验证与交付

| 检查 | 结果 |
|---|---|
| JVM | 182 项，175 通过、7 项外部探测跳过；分钟、午夜、暂停/恢复、非整数密度几何与地点去重均通过 |
| 构建/lint | Debug 与 AndroidTest APK 成功；118 warning、2 hint、0 error，与原 lint 数量一致 |
| Roborazzi | 63 项断言通过；61 张基线验证通过；44 张既有图片改变、9 张新增，变化图片逐张审阅 |
| 隔离模拟器 | 完整 45 项运行中 44 通过；场馆标题/地点同文导致旧匹配歧义，定位可点击标题后单项通过，未把分批复跑写成一次全绿 |
| 编辑与返回 | 课程半屏、聚焦展开、实际 IME 边界、备注与未保存确认；随记状态恢复/失败保留输入；日程、权限、Room 迁移/作用域、校园返回和根导航均由现有交互回归验证 |
| 系统大字号 | 临时设为系统 200% 后，课程备注保存/作用域与放弃编辑单项通过，实际 IME 边界断言通过；随后恢复原字号 |
| 长列表 | 新增 200 条长正文随记、200% 字号检查，末项与新增入口可读、可点且不重叠 |

性能对照使用同一只读 API 36 模拟器、1080×2400、默认字号、host GPU、相同固定数据与同一测试 APK，原版/优化版 App 分别覆盖安装。冷启动各预热一次，再 `am start -W` 测量 5 次：原版 2949/2769/2800/2792/2848ms，优化版 2801/2807/2898/2744/2953ms，中位数 2800/2807ms，未观察到超出该组波动的启动变化。

`gfxinfo` 在测试窗口仍存活时采集。翻周（空周/固定背景）、课程半屏到键盘、200 条随记滚动的 P50 分别为原版 250/40/23ms、优化版 200/34/17ms；帧数分别仅 18/29/11 与 18/26/7。Compose 自动化推进时钟、Debug 与模拟器调度使这些小样本不适合作真实帧率或退化结论，原始输出保留供定位参考。首次软件渲染器采样拖慢整个系统，已单独保留并弃用于比较；没有把它解释为应用问题。真机 Release 连续翻周与密集课程帧时仍待现场测量。

本轮候选版本为 1.2.3/code 7，交付流程为当前提交的 `CI result` 通过后快进合入 main，再由候选工作流准备原签名 APK。正式发行仍由用户在 Android 版本管理页验收并授权。本轮不执行后端生产部署。

### 托管 Gradle 检查的问题与答案

全部命令通过 `gradle_run.py` 托管，仅读取有界摘要。失败后根据具体源码或测试报告修正再运行，没有重开完整 Gradle 日志。
托管工作流已结束，仅清理 wrapper 自己拥有的完整日志；源码、截图和验收产物保留。

| `--question` 原文 | 结果 |
|---|---|
| “Do the unchanged Android UI screenshot baselines verify before the polish changes?” | 相对 Windows wrapper 路径失败，改为绝对路径后验证成功 |
| “Do fresh renders of the unchanged Android UI match the baseline before implementation?” | 强制重新渲染后通过，保存本轮优化前图片 |
| “Do the timetable lifecycle, geometry, and shared typography changes compile?” | 首次遗漏 PeriodAxis 参数，定位修正后被后续专项测试的编译覆盖 |
| “Do timetable minute updates, viewport geometry, and existing projection regressions pass?” | 通过 |
| “Do adaptive charts, shared feedback, campus details, and schedule cards compile together?” | 首次缺少布局导入，定位后补齐 |
| “Do the campus charts and adaptive detail layouts compile after the import corrections?” | 通过 |
| “Do all screenshot interactions pass while recording the intentionally changed UI baselines?” | 58 项断言通过，Windows 生成输出重复拷贝使收尾失败；仅移开 build 内过期生成物 |
| “Does screenshot recording finish with clean generated artifacts after the Windows file collision?” | 收尾通过 |
| “Do minute, midnight, lifecycle and geometry regressions pass after timetable updates?” | 修正嵌套作用域变量及测试默认 Application 的 Keystore 初始化后通过 |
| “Do revised timetable, chart and large-font form screenshot fixtures render and pass their behavior assertions?” | 修复短行开始时间裁切和测试根 Surface 的最小宽约束后，63 项通过 |
| “Do the full JVM suite, debug lint, app build and instrumentation build pass for the completed UI changes?” | 182 项无失败；两类 APK 构建与 lint 通过 |
| “Does the screenshot verification pass and does the instrumentation APK include readable renderer diagnostics?” | 61 张基线验证通过，测试 APK 构建通过；诊断采集随后由同数据模拟器回归验证 |
| “Does the instrumentation APK compile after matching venue headers by their click semantics?” | 构建通过；场馆单项随后通过 |

## 仍需现场核验

当前依据源码、固定数据截图、可控时钟及隔离模拟器。没有同期 iOS 真机画面或运行测量，不宣称两端同等流畅。真机 TalkBack 朗读、厂商通知投递/重启/省电、真实学校会话过期、校园网络与全部照片组合仍需现场核验。现有回归覆盖草稿、权限与身份隔离，不替代这些外部情形。360/393/412dp 与 600/840dp 的特定组合均有证据，但没有穷举每页 × 每尺寸 × 每主题 × 每字号的全笛卡尔积。
