# MyLeafy Android 对照式 UI 精修

> 状态：实施与验收进行中。本文只登记三类内容：已观察（来源 + 版本 + 日期）、代码事实（文件 + 符号，必要时行号）、真实执行过的结果。没有真跑过的检查、没有人工审阅过的截图，一律保持“待执行 / 待审阅”，不接受批量重录当作验收。
>
> 参照建立时间：2026-09-14。相关规范：[UI 风格规范](ui-style-guide.md) · [UI 设计总结](ui-implementation.md)。

## 1. 目标与边界

本轮是在既有两轮 Android UI 精修基础上的对照式收敛，不是重新设计。目标有两件事：让 Android 保留原生交互的同时达到与当前 iOS 同等级的精致度；把设计系统从“已经可用”推进到“每个页面都按同一套 token、组件和状态规则表达”。

冻结不动：

- 业务逻辑、数据层、请求时机、Repository 与 ViewModel 契约。
- 根导航顺序 `课表 / 社区 / 日迹 / 校园 / 我的`（`navigation/RootTab.kt:29-58`）、返回栈、状态恢复、深链与 capability 门控（约束见 `state/ARCHITECTURE.md` §11）。
- 系统字体与现有品牌配色。不新增主题设置，不引入动态取色。
- Android 课表的 5/7 天、13 节单屏、20 周 `HorizontalPager`、冲突投影与点击行为。

允许改的只有呈现层：token、共享组件、页面间距与层级、状态呈现、截图基线。

分工：实现、重复迁移与测试补充交给 Flash；设计判断、接口边界、截图审阅与最终 QA 由 Astra 负责，本文件由 Astra 维护。实现者与审阅者都不是唯一工作者，任何人不得回退他人的改动。

## 2. 证据规则

本文区分三类内容，逐页记录必须沿用：

| 类型 | 写法 | 例子 |
|---|---|---|
| 已观察 | 写清来源、版本、日期 | 官方商店截图第 5 张（深色时间轴） |
| 代码事实 | 给出文件与符号，必要时补行号 | `ui/theme/Type.kt` 的 `MyLeafyTypography` 覆盖 11 个 Material 角色 |
| 推断或待验证 | 明确标为“待验证 / 待执行” | 200% 字体下时间轴 9sp 的截断风险 |

参照图必须注明出处与版本；代码推断不得写成实机观察。Google Play 截图会随地区、设备与 A/B 实验变化，本文记录的是 2026-09-14 `hl=en` 的一次快照，不能推广为所有地区都成立。

行号是 2026-09-14 工作区快照。`Type.kt`、`Tokens.kt`、`LeafyComponents.kt`、各页面文件仍在被并行编辑，行号会漂移；漂移时以符号名和本文描述的行为为准，符号名不存在时以代码为准并修文档。

## 3. 四个对照基准

### 3.1 MyLeafy iOS（当前源码，不是旧官网截图）

品牌与设计 token 基准来自当前 SwiftUI 源码，而不是官网上的四入口旧截图。旧官网图只作早期品牌参考，既不代表当前 iOS 根导航，也不作为 Android 的迁移目标。

已观察的 iOS 事实：

| 内容 | 位置 |
|---|---|
| 主题偏好与鼠尾草绿默认值 | `leafy/App/Theme/AppTheme.swift:133-162`、`:230` |
| 圆角 24/16/12、间距 20/24/16/12/8 | `leafy/App/Theme/AppTheme.swift:521-535` |
| 字号 32/26/20/18/16/14/11 与字重 | `leafy/App/Theme/AppTheme.swift:571-624` |
| 缩放字体 modifier（Dynamic Type + App 密度） | `leafy/App/Theme/AppTheme.swift:599-624` |
| 课表周网格与连续日期列 | `leafy/Features/Timetable/Presentation/Grid/`、`Screen/TimetableView.swift` |
| 课表课程块与冲突 lane | `leafy/Features/Timetable/Presentation/Grid/TimetableCourseBlocks.swift` |
| 社区信息流卡片 | `leafy/Features/Community/Presentation/CommunityPostCardViews.swift`、`CommunityRootView.swift` |

迁移的是品牌配色、字体层级、留白节奏、低噪声表面和克制感。不复制 iOS Tab Bar、SF Symbols、Liquid Glass、四入口结构或玻璃导航。

### 3.2 Google Calendar Android（官方商店页）

官方来源：<https://play.google.com/store/apps/details?id=com.google.android.calendar&hl=en>

查看方式：通过内置浏览器直接打开官方 `play-lh.googleusercontent.com` 图片 URL 查看；未把图片下载进仓库，未绕过任何显示限制。该列表的 `alt` 文本统一为 “Screenshot image”，所以下面编号来自页面 DOM 顺序，不是 Google 给出的语义标签。

2026-09-14 快照中实际查看过的图片（`=w1052-h592` 为 2x 版本）：

| # | 内容（观察结论） | 官方 URL |
|---|---|---|
| 0 | 日程流：日期标记 + 彩色事件块 + 图片事件 | `https://play-lh.googleusercontent.com/5sVZzBzch4nuyTKZoCAguLBMeUtmDEoLVw9D0SjUpLv1PTLxe6uzxvPrVz7ix6gPjiWwvdF1ljHi4SxmBfk9hw=w1052-h592` |
| 4 | 月网格：周一为起始的日期头，事件 chip 横向铺满 | `https://play-lh.googleusercontent.com/lgXk86QTxH5QmaM4tsZ-AbpRIRZXlytWtiBsuv3gGOi6YFngi6Yq4q5uhJNt4AdUI8pYH_J0PNgJlPPzAdN0B80=w1052-h592` |
| 5 | 深色日程时间轴：左侧小时刻度，右侧事件块，当前时间有横线 | `https://play-lh.googleusercontent.com/3COZPcpiR2VqlyZ4-9vCALcw5TtVrN3NLOT7rSRG6PQgw5DjO-0sWr2uRNLz_W4ws741ZErBxzad9UUOHusaWA=w1052-h592` |
| 6 | 视图切换菜单：`Schedule / Day / 3 Day / Week / Month` | `https://play-lh.googleusercontent.com/4_vVundk_UOpxGElaS_52oLXO4e0Llif03NinRzYuNU0_v0OskSXMrd8FJkDus_xB_mHqW1AOMcN1zCxqqDH=w1052-h592` |
| 8 | 平板/折叠屏双栏：左月历 + 右日程时间轴 | `https://play-lh.googleusercontent.com/3xXvwU6WfThgL9yWLfujdUguh7KEBrm7VMXTekh4cY9jYu7qQryTqvMNSd4rW-1v_olfgt9oXOvklBMtCQdd=w1052-h592` |
| 12 | 平板月网格：星期表头 + 日期网格 + 事件 chip 密度 | `https://play-lh.googleusercontent.com/ZXN6mNNL30gh7MIlILhz8xyUzvp7blDgPt4PA2ruWfU2kabiG5vx3VnKJXpUhtsJtTluGqayIYWC5Ev94Jfx1w=w1052-h592` |

证据缺口：这次官方列表快照里没有出现手机周网格截图。支持“周”概念的只有第 6 张视图菜单里的 `Week` 选项，以及第 5/8 张的小时时间轴。因此本文不把商店页当作周视图布局的证据来源；周网格的对照要么等 Google 在列表里放出对应截图，要么用真实设备在官方 App 中观察，二者目前都未完成。

从官方截图可迁移的呈现方式：

- 日期与时间轴优先，容器边界其次。
- 今日用实底圆形或强调色标识，但颜色不是唯一状态载体。
- 时间轴同时承担定位与密度控制，事件块在小时尺度上直接可读。
- 月/周/日程是同一数据的不同密度投影，chrome 一致。

不迁移：Material You 动态取色、Google 事件配色语义、Google 的账号与多日历管理结构。

### 3.3 Now in Android

官方仓库：<https://github.com/android/nowinandroid>

本文核对的上游 HEAD：`12f80da6518e161ed16a06a68e71fb8a873576d6`（2026-09-14 `git ls-remote` 结果）。

迁移内容限于呈现层：

- Theme 与 token 的组织方式、明暗色语义角色、字体与形状映射。
- Compose 组件边界：根 `Modifier`、slot content、状态由调用方持有。
- Edge-to-Edge 与 WindowInsets 的分工。
- Adaptive：Compact/Medium/Expanded 改变 chrome，不改变导航图。

不迁移：多模块架构、动态取色策略、NiA 自身的品牌视觉。

### 3.4 Android 官方 Compose samples：Reply、Jetchat、Jetsnack

官方仓库：<https://github.com/android/compose-samples>

本文核对的上游 HEAD：`4c1fe7586e2fbf1c934925ef8ab64d3803361423`（`main`，2026-09-14 `git ls-remote` 结果）。

| 样例 | 只借鉴 | 不借鉴 |
|---|---|---|
| Reply | 页面层级、列表到详情的过渡、状态动效 | 邮件双栏流程与邮箱数据模型 |
| Jetchat | 信息流节奏、IME 处理、滚动中的状态保持 | 聊天气泡视觉 |
| Jetsnack | 自定义布局、细腻动效、共享元素式过渡 | 商城视觉与商品卡结构 |

## 4. 现状盘点（代码事实）

### 4.1 Typography

`android/app/src/main/java/com/myleafy/android/ui/theme/Type.kt` 用 `leafyTextStyle` 辅助函数统一了 11 个 Material 角色，并由 `Theme.kt:141` 以 `MyLeafyTypography` 注入 Compose：`displaySmall`、`headlineSmall`、`titleLarge`、`titleMedium`、`titleSmall`、`bodyLarge`、`bodyMedium`、`bodySmall`、`labelLarge`、`labelMedium`、`labelSmall`。所有角色关闭 `includeFontPadding`、把行高对齐到行盒中心，并用私有 `LeafyTracking` 区分正文、标签与微标签字距。所有角色不指定 `fontFamily`，因此继续使用系统字体，符合“保留系统字体”的要求。

课表专用紧凑角色是 `LeafyTimetableType`（`Type.kt:62` 起），不从通用按钮/标签字号复制：

| 角色 | 字号/行高 | 主要用途 |
|---|---|---|
| `LeafyTimetableType.courseTitle` | 11/14 SemiBold | 单节、行高紧张的课程名 |
| `LeafyTimetableType.courseTitleLarge` | 14/18 SemiBold | 跨节或行高充足的课程名 |
| `LeafyTimetableType.courseSubtitle` | 10/13 Medium | 地点、教师 |
| `LeafyTimetableType.courseMeta` | 12/16 Regular | 备注、周次 |
| `LeafyTimetableType.dayNumber` | 14/18 SemiBold | 今日圆点内的日号 |
| `LeafyTimetableType.axisTime` | 9/11 Medium | 节次时间轴 |

通用角色的映射：`displaySmall` 用于根页面或品牌标题，`headlineSmall` 用于重要二级标题，`titleLarge/titleMedium/titleSmall` 用于 section、卡片与行标题，`bodyLarge/bodyMedium/bodySmall` 用于正文到元信息，`labelLarge/labelMedium/labelSmall` 用于按钮与标签。

已核对的消费情况：`features/` 内没有 `copy(fontSize = …)` / `copy(lineHeight = …)`；`TimetableGrid.kt` 以 `LeafyTimetableType.<角色>` 形式引用 8 处（2026-09-14 快照）。剩余待办不是再造角色，而是逐页一致性与字体缩放验收。

### 4.2 Token 与表面

`android/app/src/main/java/com/myleafy/android/ui/theme/Tokens.kt` 已包含：

- `LeafySpacing`：`hairline/tiny/micro/compact/card/page/section/spacious/rootTop`。
- `LeafyElevation`：`flat/resting/floating/modal`。
- `LeafyStroke`：`progress`、`emphasis`。
- `LeafyGesture`、`LeafyTimetableTokens`、`LeafyAdaptiveTokens`、`LeafyLoginTokens`。课表文字 token 在 `LeafyTimetableType`，网格几何留在 `LeafyTimetableTokens`。
- `LeafyIconSize`、`LeafyComponentSize`（含 `topBar = 56.dp`、`minimumTouchTarget = 48.dp`、`settingsRowMinHeight = 64.dp`、`contentMaxWidth = 720.dp`、`formMaxWidth = 420.dp`、`emptyStateMaxWidth = 520.dp`）。
- `LeafyMotion`：`quick = 120 / standard = 220 / emphasized = 320` 与统一 easing。
- `LeafySurfaceColors(page/grouped/content/elevated/modal/accentSoft)`，Light 实现在 `Theme.kt:91`、Dark 在 `Theme.kt:100`，经 `MaterialTheme.leafySurfaces`（`Theme.kt:114`）暴露。

### 4.3 共享组件与自适应导航

`android/app/src/main/java/com/myleafy/android/ui/components/LeafyComponents.kt` 已提供：`LeafyRootTopBar`、`LeafySecondaryScaffold`、`LeafyActionIconButton`、`Modifier.leafyMinimumTouchTarget`、`LeafySectionHeader`、`LeafyContentSurface`、`LeafyToolRow`、`LeafySettingsRow`、`LeafyFeatureCard`、`LeafyLoadingState`、`LeafyEmptyState`、`LeafyErrorState`、`LeafyStatusBanner`、`LeafySnackbarHost`、`LeafySheetContent`、`LeafyPrimaryButton`、`LeafySecondaryButton`、`LeafyTextButton`、`LeafyDestructiveButton`、`LeafySettingsDivider`、`LeafySettingsGroup`、`LeafyAdaptiveContent`、`LeafyAlertDialog`、`LeafyModalBottomSheet`。

根导航由 `NavigationSuiteScaffold` 承担（`navigation/MyLeafyNavHost.kt:330`）：Compact 使用 Bottom Navigation，Medium/Expanded 使用 Navigation Rail，根目的地集合来自 `RootTab.entries`。

### 4.4 截图基线与用例现状

`android/app/src/test/screenshots/` 当前磁盘上仍只有本轮之前的 10 个 PNG：Design System 的 `componentsLight`、`componentsDark`、`componentsFontScale130`、`componentsFontScale200`；课表的 `sevenDaysWithTodayTimelineAndOverlap`、`weekdaysDark`；社区的 `contentLight`；根页面的 `scheduleEmptyLight`、`campusCompactLight`、`campusMediumLight`。

这 10 个文件已经逐字节复制为持久前图，副本放在 `assets/android-ui-polish-before/`，两者 SHA-256 相同（见 §8）。**这些图是本轮之前的基线，不是本轮结果。**

工作区已经新增或扩展以下用例（用例存在，golden 尚未生成、尚未人工审阅）：

- 课表 `TimetableScreenshotTest`：`weekdaysLongNamesConflictFontScale130`、`weekdaysFontScale200`、`weekdaysMedium600Dark`、`sevenDaysWide840LongNames`。
- 社区 `CommunityScreenshotTest`：`contentDark`、`contentWide840`、`refreshFailureKeepsContentWithLongError`、`contentFontScale200Reachability`。
- 日迹与校园 `RootContentScreenshotTest`：`scheduleEmptyDark`、`scheduleMemosLight`、`campusWide840Dark`、`campusWide600FontScale200Reachability`。
- 我的与登录 `ProfileLoginScreenshotTest`：`profileLocalLight`、`profileCommunityDark`、`profileErrorLongMessage`、`profileWide840FontScale200LogoutReachable`、`loginEmptyLight`、`loginSubmittingDark`、`loginLongErrorFontScale200Reachability`、`loginWide840KeepsFormWidth`。
- 覆盖层 `OverlayScreenshotTest`：`courseDetailsDialogLongNameLight`、`examDetailsDialogDarkFontScale130`、`memoEditorSheetLight`、`scheduleEventEditorSheetDark`、`scheduleEventDeleteConfirmLight`。
- Design System `LeafyDesignSystemScreenshotTest`（该类仍在工作区，只是被修改）：在原有 4 个 components 用例之外新增 `componentsFontScale200BottomReachability`、`extendedComponentsLight`、`extendedComponentsDark`、`longMessagesFontScale130`、`snackbarLongMessageLight`。
- 共享夹具：`ScreenshotFixtures.kt`。

差距要分开写：用例覆盖面在补齐；磁盘 golden 仍只有旧 10 个；新增用例的 golden 未生成、未审阅；“我的”、登录、关键二级页与 Sheet/Dialog 仍没有 golden。用例名是 2026-09-14 快照，页面文件仍在被并行编辑，收尾验收时必须以当时的测试源为准逐个核对，不能照抄本节。

### 4.5 视觉字面量审计（2026-09-14 重新核对）

在 `android/app/src/main/java/com/myleafy/android/features/` 内检索：

- `.dp`：4 处非 import 用法。需要迁移的是 `campus/AcademicDetailScreens.kt:256` 的 `strokeWidth = 2.dp`；另外 3 处在 `timetable/presentation/TimetableGrid.kt`（`0.dp` 零值比较，用于判断行高是否可用），属于布局判定语义，不应机械替换。
- `.sp`：0 处。课表轴字号已经回到 `LeafyTimetableType.axisTime`。
- 直接颜色构造：1 处，`profile/TimetableBackgroundScreen.kt:193` 的 `Color.Gray` 解析失败回退。

同一时间点全 Android main 源码共有 48 处非 import `.dp`：`ui/theme/Tokens.kt` 41 处、`ui/theme/Shape.kt` 3 处（都属于 token 定义本身）、`features/` 4 处（即上面的迁移点与零值比较）。这就是“清理零散字面量”的可核对边界，不是全仓库无限扩张的重构。

## 5. 逐页四项说明

每页按同一模板记录：四项说明 → 前后截图 → 差异解释 → 真实验收记录。下面的“当前差距”基于本文写就时的代码与磁盘事实，不写成已修复。

前图路径为 `assets/android-ui-polish-before/<golden 文件名>`（持久，随文档走）；后图路径为 `../../android/app/src/test/screenshots/<golden 文件名>`（本轮生成，未生成时标“待生成”）。

### 5.1 课表

| 维度 | 内容 |
|---|---|
| iOS 对照 | 月份在左上、时间轴显示节次与起止时间、日期头承载校历与考试、今日实底、课程块低饱和多色、重叠课程并排压缩（`TimetableView.swift`、`TimetableCourseBlocks.swift`）。 |
| Android 实践 | Google Calendar 的日期优先、小时时间轴、当前时间线、事件密度；Material 3 高密度排版与 48dp 命中；宽屏沿用现有 Rail。 |
| 当前差距 | 官方 Play 快照没有手机周视图可对照，周网格只能以 iOS 源码与自身基线为准；磁盘 golden 只有旧的两个 case；工作区已加冲突长名/130%、200% 字体、600dp 深色、840dp 长名用例，但 golden 未生成与审阅，冲突窄列的省略策略仍缺视觉证据。 |
| 迁移内容 | 日期与课程成为主视觉；弱化逐格空白容器；课程名优先于地点，空间不足时省略次要信息，完整内容继续由详情与无障碍描述承载；时间轴只用课表专用紧凑文字角色；补齐上述缺失基线。 |

不改变：5/7 天、13 节单屏、20 周 Pager、冲突 lane 投影、点击与详情行为。

截图对照：

| 状态 | 图 |
|---|---|
| before · 七日含今日线与冲突 | [sevenDaysWithTodayTimelineAndOverlap.png](assets/android-ui-polish-before/com.myleafy.android.testing.TimetableScreenshotTest.sevenDaysWithTodayTimelineAndOverlap.png) |
| before · 工作日深色 | [weekdaysDark.png](assets/android-ui-polish-before/com.myleafy.android.testing.TimetableScreenshotTest.weekdaysDark.png) |
| after · 七日含今日线与冲突 | [sevenDaysWithTodayTimelineAndOverlap.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.TimetableScreenshotTest.sevenDaysWithTodayTimelineAndOverlap.png)（待生成） |
| after · 工作日深色 | [weekdaysDark.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.TimetableScreenshotTest.weekdaysDark.png)（待生成） |
| after · 长名冲突 130% 字体 | [weekdaysLongNamesConflictFontScale130.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.TimetableScreenshotTest.weekdaysLongNamesConflictFontScale130.png)（待生成） |
| after · 200% 字体 | [weekdaysFontScale200.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.TimetableScreenshotTest.weekdaysFontScale200.png)（待生成） |
| after · 600dp 深色 | [weekdaysMedium600Dark.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.TimetableScreenshotTest.weekdaysMedium600Dark.png)（待生成） |
| after · 840dp 长名 | [sevenDaysWide840LongNames.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.TimetableScreenshotTest.sevenDaysWide840LongNames.png)（待生成） |

差异解释：待前图与已审阅后图并排填写。验收记录：待执行。

### 5.2 社区

| 维度 | 内容 |
|---|---|
| iOS 对照 | 作者/时间 → 分类 → 标题 → 正文摘要 → 图片 → 互动区 的稳定阅读顺序；卡片承载重复内容；发布与详情分层（`CommunityPostCardViews.swift`、`CommunityRootView.swift`）。 |
| Android 实践 | Jetchat 的信息流节奏与 IME 处理；Reply 的列表到详情层级；图片占位避免滚动抖动。 |
| 当前差距 | 社区磁盘 golden 只有 `contentLight`；工作区已加 `contentDark`、`contentWide840`、`refreshFailureKeepsContentWithLongError`、`contentFontScale200Reachability`，golden 未生成与审阅；筛选控件的边界强度仍未做视觉审阅。 |
| 迁移内容 | 调整作者、分类、标题、正文与互动区的间距和字重；降低筛选控件的边框存在感；保持平坦信息流；统一详情、评论、搜索、通知与编辑页面的视觉层级。 |

截图对照：

| 状态 | 图 |
|---|---|
| before · 浅色 360dp | [contentLight.png](assets/android-ui-polish-before/com.myleafy.android.testing.CommunityScreenshotTest.contentLight.png) |
| after · 浅色 360dp | [contentLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.CommunityScreenshotTest.contentLight.png)（待生成） |
| after · 深色 | [contentDark.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.CommunityScreenshotTest.contentDark.png)（待生成） |
| after · 840dp | [contentWide840.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.CommunityScreenshotTest.contentWide840.png)（待生成） |
| after · 刷新失败保留内容 + 长错误 | [refreshFailureKeepsContentWithLongError.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.CommunityScreenshotTest.refreshFailureKeepsContentWithLongError.png)（待生成） |
| after · 200% 字体可达性 | [contentFontScale200Reachability.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.CommunityScreenshotTest.contentFontScale200Reachability.png)（待生成） |

差异解释：待填写。验收记录：待执行。

### 5.3 校园／学业

| 维度 | 内容 |
|---|---|
| iOS 对照 | 成绩、考试、培养方案优先；领域切换用 chip；数据页显示学期、更新时间与来源；统计同时提供文字摘要与数值明细。 |
| Android 实践 | Material 3 列表与分组；宽屏沿用现有侧栏（`LeafyAdaptiveTokens.twoPaneBreakpoint = 600.dp`、`campusSidebarWidth = 184.dp`）；NiA 的 token 与 adaptive chrome 分离。 |
| 当前差距 | `AcademicDetailScreens.kt:256` 仍有 `2.dp` 描边字面量；校园磁盘 golden 仍是 `campusCompactLight`、`campusMediumLight` 两个浅色 case；工作区已加 `campusWide840Dark` 与 `campusWide600FontScale200Reachability`，golden 未生成与审阅，长数据与失败状态仍无基线。 |
| 迁移内容 | 统一领域选择、工具行、成绩统计与明细列表；优先成绩、考试、培养方案，再覆盖体育、医疗、评价等现有页面；减少重复标题与大图标底板；用 `LeafyStroke.emphasis` 替换描边字面量。 |

不改变：一级领域固定为学校教学、自习安排、体育相关、医疗事项、评价相关，以及 capability 与请求边界。

截图对照：

| 状态 | 图 |
|---|---|
| before · Compact 浅色 | [campusCompactLight.png](assets/android-ui-polish-before/com.myleafy.android.testing.RootContentScreenshotTest.campusCompactLight.png) |
| before · Medium 浅色 | [campusMediumLight.png](assets/android-ui-polish-before/com.myleafy.android.testing.RootContentScreenshotTest.campusMediumLight.png) |
| after · Compact 浅色 | [campusCompactLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.RootContentScreenshotTest.campusCompactLight.png)（待生成） |
| after · Medium 浅色 | [campusMediumLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.RootContentScreenshotTest.campusMediumLight.png)（待生成） |
| after · 840dp 深色（有数据） | [campusWide840Dark.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.RootContentScreenshotTest.campusWide840Dark.png)（待生成） |
| after · 600dp 200% 字体可达性 | [campusWide600FontScale200Reachability.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.RootContentScreenshotTest.campusWide600FontScale200Reachability.png)（待生成） |

差异解释：待填写。验收记录：待执行。

### 5.4 日迹

| 维度 | 内容 |
|---|---|
| iOS 对照 | 顶部直接提供 `随记 / 日程 / 推送`；随记卡片使用系统表面；编辑表单与列表分区明确。 |
| Android 实践 | Material 3 顶部 section 切换与状态保持；Jetchat/Reply 的 IME 与表单可达性；空状态说明“什么为空、为什么、下一步”。 |
| 当前差距 | 日迹磁盘 golden 只有 `scheduleEmptyLight`；工作区已加 `scheduleEmptyDark`、`scheduleMemosLight`，golden 未生成与审阅；随记/日程/推送三段、编辑表单与 IME 仍无截图或 instrumentation 证据。 |
| 迁移内容 | 统一随记、日程、推送的顶部节奏、列表、空态与编辑表单；保留现有状态与切换行为；为 `MemoEditorSheet`、`ScheduleEventEditorSheet` 增加 IME 可达性验证。 |

截图对照：

| 状态 | 图 |
|---|---|
| before · 空态浅色 | [scheduleEmptyLight.png](assets/android-ui-polish-before/com.myleafy.android.testing.RootContentScreenshotTest.scheduleEmptyLight.png) |
| after · 空态浅色 | [scheduleEmptyLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.RootContentScreenshotTest.scheduleEmptyLight.png)（待生成） |
| after · 空态深色 | [scheduleEmptyDark.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.RootContentScreenshotTest.scheduleEmptyDark.png)（待生成） |
| after · 有随记（浅色） | [scheduleMemosLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.RootContentScreenshotTest.scheduleMemosLight.png)（待生成） |
| after · 随记编辑 Sheet | [memoEditorSheetLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.OverlayScreenshotTest.memoEditorSheetLight.png)（待生成） |
| after · 日程编辑 Sheet（深色） | [scheduleEventEditorSheetDark.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.OverlayScreenshotTest.scheduleEventEditorSheetDark.png)（待生成） |

差异解释：待填写。验收记录：待执行。

### 5.5 我的

| 维度 | 内容 |
|---|---|
| iOS 对照 | 使用 `List + insetGrouped`；身份与资料置顶；功能、外观、数据、支持分组；退出登录单独成组并使用危险色。 |
| Android 实践 | `LeafySettingsRow` 与 `LeafySettingsGroup` 的无外层卡片设置列表；稳定行高 `settingsRowMinHeight = 64.dp`；NiA 的表面与明暗色角色。 |
| 当前差距 | 磁盘 golden 里没有“我的”页面，前后图都缺；`ProfileLoginScreenshotTest` 已有四个用例但 golden 未生成与审阅；`ProfileScreen`、`ProfilePreferencesScreen`、`ProfileSyncScreen`、`ProfileStaticScreens` 的层级仍只由代码阅读判断。 |
| 迁移内容 | 突出身份与资料；设置采用稳定分组、统一行高与辅助文字；危险操作独立呈现；减少重复容器；补齐“我的”浅色/深色 golden。 |

不改变：退出登录清理范围与保留数据的既有语义。

截图对照（本页没有本轮之前的 golden，前图列只在生成后补记，避免拿别的页面冒充）：

| 状态 | 图 |
|---|---|
| after · 本地模式浅色 | [profileLocalLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.ProfileLoginScreenshotTest.profileLocalLight.png)（待生成，无前图） |
| after · 社区模式深色 | [profileCommunityDark.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.ProfileLoginScreenshotTest.profileCommunityDark.png)（待生成，无前图） |
| after · 长错误信息 | [profileErrorLongMessage.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.ProfileLoginScreenshotTest.profileErrorLongMessage.png)（待生成，无前图） |
| after · 840dp 200% 字体退出可达 | [profileWide840FontScale200LogoutReachable.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.ProfileLoginScreenshotTest.profileWide840FontScale200LogoutReachable.png)（待生成，无前图） |

差异解释：待填写。验收记录：待执行。

### 5.6 登录与其余二级页面

| 维度 | 内容 |
|---|---|
| iOS 对照 | 登录页居中、表单最大宽度约 360、身份分段选择、验证码图片/加载/重试状态、密码显隐、登录中禁用重复提交、错误贴近表单。 |
| Android 实践 | `LeafyLoginTokens.captchaWidth = 96.dp`、`LeafyComponentSize.formMaxWidth = 420.dp`；IME Insets 由输入区消费；Reply/Jetchat 的表单与键盘可达性。 |
| 当前差距 | 登录、Sheet、Dialog、关键二级页面仍没有 golden；`ProfileLoginScreenshotTest` 与 `OverlayScreenshotTest` 的用例已写好但 golden 未生成与审阅；验证码加载失败与键盘弹出后的主操作可达性仍无 instrumentation 证据。 |
| 迁移内容 | 统一表单、验证码、错误提示、返回栏与操作按钮；检查长内容与键盘弹出时的滚动可达性；补齐登录、Sheet/Dialog 与关键二级页面基线。 |

截图对照（本页同样没有本轮之前的前图）：

| 状态 | 图 |
|---|---|
| after · 登录空态浅色 | [loginEmptyLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.ProfileLoginScreenshotTest.loginEmptyLight.png)（待生成） |
| after · 提交中深色 | [loginSubmittingDark.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.ProfileLoginScreenshotTest.loginSubmittingDark.png)（待生成） |
| after · 长错误 200% 字体可达 | [loginLongErrorFontScale200Reachability.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.ProfileLoginScreenshotTest.loginLongErrorFontScale200Reachability.png)（待生成） |
| after · 840dp 保持表单宽度 | [loginWide840KeepsFormWidth.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.ProfileLoginScreenshotTest.loginWide840KeepsFormWidth.png)（待生成） |
| after · 课程详情 Dialog（长名） | [courseDetailsDialogLongNameLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.OverlayScreenshotTest.courseDetailsDialogLongNameLight.png)（待生成） |
| after · 考试详情 Dialog（130% 字体深色） | [examDetailsDialogDarkFontScale130.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.OverlayScreenshotTest.examDetailsDialogDarkFontScale130.png)（待生成） |
| after · 日程删除确认 | [scheduleEventDeleteConfirmLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.OverlayScreenshotTest.scheduleEventDeleteConfirmLight.png)（待生成） |

差异解释：待填写。验收记录：待执行。

需要纳入同样的验收、但目前只有代码路径的二级页面：`auth/LoginScreen.kt`、`campus/AcademicDetailScreens.kt`、`campus/CampusCalendarScreen.kt`、`campus/CampusLifeScreens.kt`、`campus/CatalogRatingsScreen.kt`、`campus/ClassroomScreen.kt`、`community/CommunityDiscoveryScreens.kt`、`community/ComposePostScreen.kt`、`community/PostDetailScreen.kt`、`profile/ProfileEditScreen.kt`、`profile/ProfilePreferencesScreen.kt`、`profile/ProfileSyncScreen.kt`、`profile/ProfileStaticScreens.kt`、`profile/TimetableBackgroundScreen.kt`、`schedule/MemoEditorSheet.kt`、`schedule/ScheduleEventEditorSheet.kt`、`timetable/presentation/TimetableDetailsDialog.kt`、`timetable/sharing/TimetableSharingScreen.kt`。

### 5.7 共享组件与状态（跨页面，先于各页执行）

这一节不是页面，而是所有页面共用的组件采样。它排在实现顺序最前面，因为页面迁移依赖它先收敛。

| 维度 | 内容 |
|---|---|
| iOS 对照 | 组件按语义命名（`leafyCardStyle`、`LeafyCapsuleChipSurface`、`LeafyOperationAlert`）；表面层级由背景与弱分隔线建立，不靠层层卡片。 |
| Android 实践 | Now in Android 的 Theme/组件边界与 slot 写法；Material 3 的 Button/List/Sheet/Dialog 语义；根 `Modifier` 由调用方传入。 |
| 当前差距 | 磁盘上仍有旧的 4 个 components golden，但采样器用例已扩展（新增 `extendedComponents*`、`longMessagesFontScale130`、`snackbarLongMessageLight`、`componentsFontScale200BottomReachability`），新旧 golden 尚未并轨，组件在深色与放大字体下的实际观感缺少已审阅证据。 |
| 迁移内容 | 统一 shape、surface、间距与 48dp 触控；普通内容默认平面，只有分组与浮层抬升；Sheet/Dialog 只使用系统动画，不叠加第二层；补齐采样器深浅色与 130%/200% 字体基线。 |

截图对照：

| 状态 | 图 |
|---|---|
| before · 采样器浅色 | [componentsLight.png](assets/android-ui-polish-before/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.componentsLight.png) |
| before · 采样器深色 | [componentsDark.png](assets/android-ui-polish-before/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.componentsDark.png) |
| before · 130% 字体 | [componentsFontScale130.png](assets/android-ui-polish-before/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.componentsFontScale130.png) |
| before · 200% 字体 | [componentsFontScale200.png](assets/android-ui-polish-before/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.componentsFontScale200.png) |
| after · 采样器浅色 | [componentsLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.componentsLight.png)（待生成） |
| after · 采样器深色 | [componentsDark.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.componentsDark.png)（待生成） |
| after · 130% 字体 | [componentsFontScale130.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.componentsFontScale130.png)（待生成） |
| after · 200% 字体 | [componentsFontScale200.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.componentsFontScale200.png)（待生成） |
| after · 扩展组件浅色 | [extendedComponentsLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.extendedComponentsLight.png)（待生成） |
| after · 扩展组件深色 | [extendedComponentsDark.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.extendedComponentsDark.png)（待生成） |
| after · 长文案 130% 字体 | [longMessagesFontScale130.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.longMessagesFontScale130.png)（待生成） |
| after · Snackbar 长消息 | [snackbarLongMessageLight.png](../../android/app/src/test/screenshots/com.myleafy.android.testing.LeafyDesignSystemScreenshotTest.snackbarLongMessageLight.png)（待生成） |

差异解释：待填写。验收记录：待执行。

## 6. Design System 收敛清单

依赖顺序：共享 token 与组件先行，页面迁移随后，每页文件不重叠分配。

| 项 | 现状（代码事实） | 本轮动作 | 状态 |
|---|---|---|---|
| Typography 角色映射 | 11 个 Material 角色（`MyLeafyTypography`）与 `LeafyTimetableType` 紧凑角色已存在 | 逐页一致性检查与字体缩放验收 | 实现已存在，验收待执行 |
| Spacing | `LeafySpacing` 完整 | 页面不再新增无语义间距；网格几何留在 `LeafyTimetableTokens` | 待执行 |
| Elevation | `flat/resting/floating/modal` | 普通内容默认平面，只有分组与浮层抬升 | 待执行 |
| IconSize | `compact/standard/prominent/touchTarget/emptyStateContainer` | 统一工具图标、空态底板与 48dp 触控 | 待执行 |
| Motion | 120/220/320ms + easing | 只用于选中、展开、反馈；Sheet/Dialog 不叠加第二层动画 | 待执行 |
| Surface | Light/Dark 双套 `LeafySurfaceColors` | 校验 page/grouped/content/elevated/modal/accentSoft 的实际使用一致 | 待执行 |
| 组件校准 | TopBar/导航/Sheet/Dialog/按钮/列表/空态/Loading/Error/Snackbar 已具备 | 统一 shape、surface、间距、slot 与根 `Modifier` | 待执行 |
| 字面量清理 | `AcademicDetailScreens.kt:256` 一处描边 `.dp`，`TimetableBackgroundScreen.kt:193` 一处颜色回退；`TimetableGrid.kt` 3 处 `0.dp` 为零值比较 | 描边替换为 `LeafyStroke.emphasis`；颜色回退改成有语义的 token 或明确说明；零值比较保留 | 待执行 |

Insets 继续按现有职责划分：根壳处理导航区域，页面处理状态栏，输入区处理 IME；已消费的 padding 不重复叠加。字体缩放不得被布局反向抵消；课表在 200% 字体下的策略是允许文字省略并由详情承载完整信息，而不是压缩系统缩放。

## 7. 验收矩阵与真实验收记录

命令与 CI 保持一致（`.github/workflows/android-ci.yml:44-54`）：

| 检查 | 命令 | 状态 |
|---|---|---|
| 构建 | `./gradlew :app:assembleDebug` | 待执行 |
| JVM 测试 | `./gradlew :app:testDebugUnitTest` | 待执行 |
| Lint | `./gradlew :app:lintDebug` | 待执行 |
| Roborazzi 验证 | `./gradlew :app:verifyRoborazziDebug -Pscreenshot` | 待执行 |
| Instrumentation 回归 | `./gradlew :app:connectedDebugAndroidTest` | 待执行 |

截图矩阵：

| 维度 | 覆盖 |
|---|---|
| 主题 | 每个根页面浅色 + 深色 |
| 尺寸 | 360dp 窄屏；600dp 与 840dp 宽屏用于重点页面 |
| 字体 | 100%、130%、200% |
| 数据 | 长课程名、冲突课程、长错误、空数据、刷新失败保留内容 |
| 外壳 | 整页外壳、“我的”、登录、关键二级页、Sheet/Dialog |

截图必须先人工视觉审阅再更新 golden，不能用批量重录代替验收。真机 ADB 目前是 `unauthorized`，本轮先用模拟器完成验证；真机验收单独标注完成状态。

真实验收记录（只登记真跑过的结果，未跑就留空）：

| 日期 | 范围 | 命令 / 操作 | 结果 |
|---|---|---|---|
| 2026-09-14 | 前图归档 | 10 个旧 golden 复制到 `assets/android-ui-polish-before/` 并核对 SHA-256 | 10/10 一致 |

## 8. 前后截图资产与命名

- 前图：`docs/design/assets/android-ui-polish-before/`，10 个 PNG，文件名与 Roborazzi 输出一致（`<全限定类名>.<用例名>.png`）。它们是本轮之前的磁盘基线逐字节副本，不重绘、不压缩、不改名；旧目录 `android/app/build/ui-polish-before/` 保留不删。
- 后图：`android/app/src/test/screenshots/`，由 `roborazzi { outputDir.set(file("src/test/screenshots")) }`（`android/app/build.gradle.kts:136-137`）指定。文档中的后图链接按同一命名规则提前写好，文件生成前标“待生成”。
- 新增用例必须先有 golden，再有链接；不得为凑表格写没有对应文件的链接而不标“待生成”。

## 9. 证据缺口与风险

- Google Calendar 官方 Play 快照没有手机周网格截图；周视图对照目前只有视图菜单中的 `Week` 选项与时间轴/月网格截图。周网格的最终对照仍需权威来源或真机观察。
- Play Store 截图随地区、设备与实验变化，本文的截图结论不写成所有地区都成立。
- 真机 ADB `unauthorized`，模拟器结果不能替代真机字体缩放、系统栏、手势导航与 IME 的最终验收。
- Android 本科课表结构变化与校园 Wi-Fi TLS 拦截是既有真实问题（见 `state/CURRENT.md`），不属于本轮 UI 范围，也不得用 UI 兜底掩盖。
- 截图用例名与文件位置在收尾时会随并行编辑变化；验收前必须按当时的测试源重新核对，不能照抄 §4.4 与 §5。

## 10. 逐页记录模板

每页完成后追加：

```text
### <页面名> · <日期>

iOS 对照：
Android 实践：
当前差距：
迁移内容：

改动文件：

前后截图：
- before（浅色 / 360dp / 100%）：assets/android-ui-polish-before/<文件>.png
- after（浅色 / 360dp / 100%）：android/app/src/test/screenshots/<文件>.png
- dark / 200% / 宽屏：

差异解释：
验收记录（命令 + 结果）：
剩余问题：
```
