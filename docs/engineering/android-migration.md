# MyLeafy Android 迁移方案

本文是 MyLeafy iOS → Android 原生迁移的设计与现状记录。Android 客户端位于仓库根目录 `android/`，单 app module，遵循「iOS behavior → Android native implementation」，**不是** Swift → Kotlin 逐行翻译。

迁移的信息来源是现有 iOS 代码（`leafy/`）、Supabase（`supabase/`）与设计文档（`docs/`）。Android 与 iOS **不共享客户端源码**；共享的是 Supabase Schema、API Contract、DTO 语义、HTML Fixture、Parser Expected Result、产品行为与错误语义。

## 0. 工程事实（已核验）

| 项 | 值 |
|---|---|
| 工具链 | Gradle 8.14.5（wrapper）+ AGP 8.13.2 + Kotlin 2.2.21 + KSP 2.2.21-2.0.5 |
| Compose | BOM 2026.01.00 + Material 3；icons-extended 固定 1.7.8 |
| SDK | compileSdk 36 / targetSdk 36 / **minSdk 29**（Android 10+） |
| JDK | 构建用 JDK 17（Android Studio 内嵌 JBR 亦可） |
| 包 | `com.myleafy.android`，versionCode 1，versionName 0.1.0 |
| 结构 | 单 `:app` module；本地 Room 库 `myleafy.db`（v4） |
| 数据层 | Room v4：Course / Grade / GradeRanking / GradeSummary / Exam / ScheduleMemo / ScheduleEvent，全部按 `scopeKey` 隔离；DataStore Preferences（非敏感设置） |
| 导航 | 5 个根 Tab（社区按 capability 隐藏）+ `login` 路由 + 深链（`myleafy://community-post` / `timetable-invite`） |
| 验证 | Android CI 与本地包装器执行 `assembleDebug` / `testDebugUnitTest` / `lintDebug`；API 36 执行 scoped Room 与 Compose 导航测试 |

阶段 1 交付：可编译、可运行、5 Tab 可导航、架构（Compose → ViewModel → Repository → DataSource）正确的工程骨架。
阶段 1.5 交付：全部功能的基础架构（UiState 状态机 / Repository / Room / DTO / 登录路由 / 深链）已搭好，教务网络与 Supabase 仍未接入（占位实现如实展示“未接入”文案）。
**阶段 2（M2.1-M2.5）已完成：** OkHttp 教务客户端与 Cookie 契约 → 强智登录（encodeKey/验证码/会话验证）→ 课表抓取 + jsoup 解析（contracts fixtures 回归）+ Room 落库 → 周课表网格渲染 → 成绩/考试抓取 + 校园页。`assembleDebug` + `testDebugUnitTest`（67 用例）通过。
**阶段 4 社区核心体验已完成：** supabase-kt 客户端层（auth/postgrest/functions，匿名 Auth + bootstrap + feed）→ 帖子详情 + 评论线程 + 点赞 → 文本发帖 + 评论；继续接入分类、近七日热门、稳定下拉刷新、搜索、通知未读/已读、收藏、本人内容软删除、举报与屏蔽。UI 只调用仓储，数据和治理仍由现有 RLS / Edge Function / RPC 契约约束。
**Android 原生 UI 壳已完成一轮收敛：** 5 个根 Tab 使用 Material 3 根页面；底栏仅在根目的地显示，二级页面统一返回栏；`FeatureDestination` 为待接入能力提供明确占位。帮助中心、权限说明、关于与内置校历为完整静态页面。所有业务列表只展示真实数据，不写入演示内容；校园网相关能力允许以空状态完成 UI 验收。

**核心对齐基础层（2026-08-30）：** Android launcher 图标由 iOS `AppIcon.png` 唯一母版生成 legacy/adaptive/monochrome 资源；Material 3 统一使用 12/16/24dp 品牌圆角。`ActiveAppScopeStore` 统一身份、guest 与 capability，Room v4 的全部本地实体以 `(scopeKey, id)` 隔离，仓储随活动作用域切换；Supabase 仅在身份具备社区 capability 时延迟初始化。Android 尚未发布，因此 schema 1–3 允许破坏性重建，此后缺 migration 必须失败。

**课表与个人日程对齐（2026-08-30）：** `TimetableGridProjection` 统一投影课程、考试与个人日程的 day/period span/lane/stable ID，稳定 Compose `Layout` 渲染 7 天 × 13 节紧凑圆角网格；周卡只保留左右切换，“回到本周/同步课表”位于右上角菜单。课表和日迹共用 scoped Room 日程并支持增删改、重启持久化；课程周次与学期范围内个人日程以 `Asia/Shanghai` 导出 RFC 5545 ICS，通过受限 FileProvider 和 Android Sharesheet 分享，不申请日历写入权限。

**社区核心体验对齐（2026-08-30）：** `CommunityViewModel` 以不可变状态区分初次加载、刷新、可信空结果和保留旧内容的失败；普通 Feed 支持分类/搜索，热门严格使用服务端支持的独立 `mode=hot&days=7`。真实通知页按 recipient RLS 读取并支持单条/全部已读与帖子导航；详情页收藏、软删除、举报和屏蔽均经 `CommunityRepository` 调用现有 RPC。自定义校园必须已批准，互动前必须完成资料；guest 仍不初始化 Supabase。

**API 36 设备验收（2026-08-30）：** Pixel 8 / Android 16 模拟器已通过 12 个 instrumentation 用例（根导航、scoped Room 重开、课表格子/课程块点击、日程编辑/删除确认、社区筛选点击与失败保留旧内容）。真实旅程完成空白格新增日程、强制结束后持久化、日迹共享显示与 ICS Sharesheet；guest 隐藏社区，校园 capability 身份的导航测试确认社区及真实搜索二级页可达。此前真实本科验证码和登录修复继续有效。当前 `xskb_list.do` 的真实响应不含 Android 解析器支持的 `kbcontent/kbtable` 结构，按契约报数据不可用并保留缓存；iOS 表单/WebView bootstrap 回退仍属后续教务专项。

## A. 迁移清单（Migration Inventory）

### 可直接复用（行为契约照搬）

- **强智登录协议**：`encodeKey` 密码混淆算法（`account%%%password` 与 `#` 分割的 key 交错）、`Logon.do` 三步流程、`RANDOMCODE` 验证码。
- **研究生系统**：`/home/stulogin` 取 `#pubkey`（RSA 2048），登录响应 AES-128-ECB（key `southsoft12345!#`）解密，成功判定 `jg == "1"` 且 `url` 非空。
- **Cookie 契约**：应用自持名值对字典为事实来源，请求显式带 `Cookie` 头（按名称排序、`"; "` 拼接），响应 `Set-Cookie` 逐条合并持久化。
- **全部 HTML 解析规则**：CSS 选择器、单元格索引映射、正则、UTF-8→GB18030 回退、`verifiedEmpty`（可信空）与 `tableRowsUnparseable`（非空不可解析）区分。
- **页面识别标记**：`isLoginPage` / `isAuthenticatedResponse` / `isTimetablePage` / `isExamSchedulePage` / `isEmptyClassroomPage`。
- **错误语义**：`loginFailed / sessionExpired / campusNetworkRequired / timetableDataUnavailable / …`。
- **Supabase 契约**：Edge Function 名、RPC 名与参数（`p_` 前缀 snake_case）、表字段 snake_case、RLS 模型（`current_profile_id()` / campus_id 作用域 / 完整资料与社区准入门控）。
- **校园能力模型**：`CampusID / CampusCapability / CampusDescriptor`，`.bjfu` 全能力、`.custom` 子集；capability 门控功能入口。
- **本地数据隔离**：按 `CampusIdentity.scopeKey`（SHA-256 前 12 位 hex）隔离 Room 库、偏好与凭据。

### 需要重写（逻辑保留、形态重做）

- 课表投影（`TimetableGridSnapshot` / 重叠课程布局）→ 纯 Domain `TimetableGridProjection` + 稳定 Compose `Layout` 网格，不使用实验性 Grid/LazyLayout API。
- 日迹随记/统计/语音转写/分享图 → Android 原生能力（MediaStore、SpeechRecognizer、Canvas 生成）。
- Widget、分享扩展、导入扩展 → Android Widget / Glance、系统分享，后续阶段。
- 社区发布队列（重试幂等）→ 保留语义，用 WorkManager + Room 重做。

### 需要替换 Android API

| iOS | Android |
|---|---|
| SwiftUI | Jetpack Compose + Material 3 |
| SwiftData | Room（KSP） |
| URLSession | OkHttp（自定义 CookieJar，复刻 iOS Cookie 头） |
| SwiftSoup | jsoup（CSS 选择器语法一致） |
| WKWebView | `android.webkit.WebView`（注入 Cookie + 隐藏 WebView 课表兜底） |
| Keychain | Android Keystore AES-GCM（`SecureStorage`） |
| UserDefaults JSON 缓存 | DataStore Preferences + Room |
| supabase-swift | supabase-kt（postgrest-kt / auth-kt / functions-kt） |
| WeatherKit | `campus-weather` Edge Function（同后端，非 Apple 专属） |
| WidgetKit | Glance |
| Background Task | WorkManager |
| NavigationStack / TabView | Navigation Compose / NavigationBar |

### 暂时不迁

社区发布队列、评教/评课/评菜目录、学习空间/专注记录/职业/医疗等本地记录、运营后台、分享与导入扩展、Widget。

### 高风险

- 强智 `encodeKey` 加密算法与登录页结构变化。
- Cookie 持久化隔离（按身份 scopeKey）必须严格保持一致。
- 教务 HTML 结构变化导致的解析失效（iOS 同样面临，靠 Fixture 回归样本覆盖）。
- 研究生 AES 解密链路（RSA + AES-ECB）。
- 社区身份引导：匿名 Supabase Auth → `community-bootstrap-user` → profile 继承。
- 纯 HTTP 教务站点：Android 需 network-security-config 白名单放行两域名。

## B. 平台映射（Platform Mapping）

| 概念 | iOS | Android |
|---|---|---|
| UI | SwiftUI（`leafyApp`/`ContentView`/Feature Views） | Compose（`MyLeafyApp`/`MyLeafyNavHost`/Feature Screens） |
| 状态 | ObservableObject + @StateObject | ViewModel + StateFlow + collectAsState |
| 组合根 | `LeafyDependencies`（EnvironmentValues） | `AppContainer`（Application 持有，`appViewModelFactory` 注入） |
| 本地库 | SwiftData（每身份一 store） | Room（`myleafy.db`） |
| 键值缓存 | UserDefaults（campus 作用域 key） | SharedPreferences / DataStore |
| 凭据 | Keychain | Android Keystore AES-GCM |
| 网络 | URLSession + HTTPCookieStorage | OkHttp + 自定义 Cookie 策略 |
| 解析 | SwiftSoup（`HTMLParser.swift`） | jsoup（`HtmlParser` 接口） |
| WebView | WKWebView（`TimetableWebViewBootstrapper`） | android.webkit.WebView |
| 后端 | supabase-swift v2.44.1 | supabase-kt（阶段 2） |
| 导航 | TabView + NavigationStack | NavigationBar + NavHost |
| 主题 | `AppTheme`（鼠尾草绿默认） | M3 `MyLeafyTheme`（#9DC183 种子） |

## C. 依赖计划（Dependency Plan）

只选成熟维护良好的库；优先 Android 官方。

**阶段 1 已接入：** compose（ui/material3/icons-extended）、navigation-compose、lifecycle（runtime/viewmodel-compose）、activity-compose、core-ktx、room（runtime/ktx/compiler via KSP）、datastore-preferences、junit（测试）。

**版本目录已锁定、阶段 2 按需接入：** okhttp 4.12.0（5.x 需 compileSdk 37，与 AGP 8.13.2 上限冲突）、jsoup 1.23.1。

**阶段 2 评估：** supabase-kt（postgrest/auth/functions）、datastore-preferences、coil（图片加载）、workmanager。

**明确不引入：** Hilt/Koin（除非多模块）、Service Locator、自制 DI 框架、BaseViewModel/BaseRepository/Generic Wrapper、Kotlin Multiplatform、Compose Multiplatform。

## D. 阶段 1 实施内容

已完成，见「0. 工程事实」与下述目录：

```
android/
├── settings.gradle.kts / build.gradle.kts / gradle.properties
├── gradle/libs.versions.toml          # 版本目录
├── gradle/wrapper/ + gradlew          # Gradle 8.14.5
├── secrets.properties(.example)       # Supabase URL + anon key（git-ignore 真实值）
├── README.md                          # 构建说明
└── app/
    └── src/main/
        ├── AndroidManifest.xml        # 含 network-security-config 与 myleafy:// 深链
        ├── res/                       # 字符串、主题、自适应启动图标
        └── java/com/myleafy/android/
            ├── MyLeafyApplication.kt / MainActivity.kt
            ├── ui/theme/              # M3 亮/暗，鼠尾草绿
            ├── ui/MyLeafyApp.kt / ui/components/
            ├── navigation/            # RootTab + MyLeafyNavHost + Routes（5 Tab + login + 深链）
            ├── features/
            │   ├── auth/              # 登录表单 + 状态机（阶段 2 接强智）
            │   ├── timetable/         # domain（SemesterConfig/PeriodSchedule）+ Room 数据链路
            │   ├── community/         # DTO（shared/model）+ 仓储接口 + 占位页
            │   ├── schedule/          # 随记/日程 Room CRUD（本地权威，真实可用）
            │   ├── campus/            # 成绩/考试 Room 缓存 + 占位页
            │   └── profile/           # 本地身份 + 社区资料占位
            ├── core/
            │   ├── campus/            # CampusID/Capability/Descriptor/ActiveAppScopeStore
            │   ├── data/local/        # Room v4：全部实体按 scopeKey 隔离
            │   ├── di/                # AppContainer + appViewModelFactory
            │   ├── network/           # 教务客户端接口/Cookie 契约/错误/身份 scopeKey
            │   ├── prefs/             # SettingsStore（DataStore：身份/主题/语言）
            │   ├── security/          # SecureStorage（Keystore AES-GCM）+ 凭据/Cookie 存储
            ├── parsers/               # HtmlParser 接口 + 解析结果类型
            ├── services/              # SupabaseConfig（BuildConfig ← secrets.properties）
            └── shared/model/          # 社区 DTO（snake_case，跨平台契约）
```

### 阶段 1.5 架构要点

- 每个功能都有独立 `sealed UiState`（Loading / Loaded / Empty / Error），满足「新功能必须定义 Loading、Empty、Error 与恢复行为」不变量。
- 依赖方向：Compose UI → ViewModel → Repository → Room/DataStore/占位；无 UseCase 泛滥、无 Base 类。
- 日迹（Schedule）为真实可用的本地功能：随记新增/编辑/软删除与标签保存；个人日程新增/编辑/删除，和课表共用 Room 持久化数据源。
- 登录路由 `login` 已接入 NavHost；Profile 页提供入口，阶段 2 替换为强智登录协议。
- 深链 `myleafy://community-post?id=…` 与 `myleafy://timetable-invite?code=…` 挂靠社区/我的 Tab（对应 iOS 深链路由白名单）。
- 占位仓储（Community/Auth/Profile）通过 `isPlaceholder` 标识在 UI 如实展示“未接入”，不静默返回假数据。
- 纯逻辑（学期周次、节次时段、Cookie 契约）已单元测试覆盖。

### 架构决策

- 依赖方向固定：`Compose UI → ViewModel → Repository → DataSource`；无 UseCase 泛滥、无 Base 类。
- 根导航逻辑顺序为课表/社区/日迹/校园/我的；社区按 `ActiveAppScope` capability 门控，guest/无能力身份不显示社区且不初始化 Supabase。
- 本地数据分类：教务副本（Course/Grade/Exam，学校权威）与用户数据（ScheduleMemo/ScheduleEvent，本地权威）分实体注册，社区数据以 Supabase 为权威不落 Room。
- Android 未发布测试数据只允许 schema 1–3 破坏性重建；其他缺失 migration 必须直接失败，不能静默清库。

## 数据模型映射表（DTO / Entity）

「Swift Type / Android Type / 关键字段 / 本地持久化 / 跨平台共享」详见下表。**纯 UI/Domain 投影不进入 Android 数据模型**（如 `TimetableGridSnapshot`、`TimetableGridProjection`、`GradeAnalytics`、`ScheduleMemoStatistics`）。

### 教务本地数据

| Swift Type | Android Type | 关键字段 | 持久化 | 跨平台 |
|---|---|---|---|---|
| `Course`（@Model） | `CourseEntity`（Room） | id, sourceSemesterID, courseName, teacher, classInfo, room, location, dayOfWeek(1-7), weeks:[Int], duration:[Int]（均非空） | SwiftData→Room | ✗（教务副本） |
| `SharedTimetableCourse`（Codable） | DTO | course_name, day_of_week … | ✗ | ✓（共享课表） |
| `Grade`（@Model） | `GradeEntity`（Room） | term, courseName, **credit:String, score:String**（保持原始串） | SwiftData→Room | ✗ |
| `ExamArrangement`（JSON 缓存） | `ExamEntity`（Room） | id:Int, courseID, name, date/start/end/location | JSON→Room | ✗ |
| `CustomScheduleEvent`（个人日程，iOS 为 UserDefaults JSON） | `ScheduleEventEntity`（Room） | id, title, startsAt, endsAt?, location?, note?, minutesBefore | ✓ | ✗ |
| `ScheduleMemo`（@Model） | `ScheduleMemoEntity`（Room） | body, kind, title?, tags, createdAt/updatedAt, pinnedAt?, trashedAt?, linkedSchedule… | ✓ | ✗ |
| `CampusIdentity` | data class | campusID, eduID, portal, kind, scopeKey(SHA-256) | Keystore+Prefs | ✗ |
| `SemesterRuntimeConfig`（Codable） | data class | semester_id, semester_start_date, supported_weeks, graduate_timetable_term_code, calendar_events | 缓存 | ✓（`semester_runtime_configs` 表） |

### 社区（Supabase，snake_case，跨平台共享）

| Swift Type | Android Type | 来源表 |
|---|---|---|
| `CommunityProfile` | `ProfileDto` | `profiles` |
| `CommunityPost` / `CommunityPostPin` / `CommunityPostImage` / `CommunityPostAttachment` | `PostDto` 等 | `posts` / `post_images` / `post_attachments` |
| `CommunityComment` | `CommentDto` | `comments` |
| `CommunityNotification` / `SiteAnnouncement` / `CommunityBanner` | DTO | `community_notifications` 等 |
| `SharedTimetableSnapshot` / `TimetableShareMember` / `TimetableInvite` | DTO | `timetable_snapshots` 等 |

> 时间戳表示不统一：社区 DTO 用 ISO-8601 String；SwiftData 模型用 Date；`ExamArrangement` 用 date/start/end 拆分字符串。Android 模型按来源保留原始形态，仅在展示层解析。

## 教务协议记录（JWXT）

行为事实来源：`leafy/Services/SchoolNetworkManager*.swift` + `leafy/Parsers/HTMLParser.swift`。阶段 2 由 OkHttp + jsoup 复刻，**不得凭猜测重设计**。

### 基础设施

| 项 | 本科（强智） | 研究生（gmis5） |
|---|---|---|
| Base URL | `http://newjwxt.bjfu.edu.cn` | `http://gradms.bjfu.edu.cn/gmis5` |
| 时区 | Asia/Shanghai | 同左 |
| UA | `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36` | 同左 |
| Referer | `http://newjwxt.bjfu.edu.cn/`（全局默认） | 各请求自带 |

网络策略：`reloadIgnoringLocalCacheData`、请求超时 8s / 资源 18s、`Cache-Control: no-cache` + `Pragma: no-cache`。Android 用 OkHttp `cache = null` + `noCache()`。

### Cookie 处理（关键）

1. 应用自持 `Map<String,String>` 为事实来源，持久化于 Keystore（`SchoolSessionCookieStore`，键 = `scopeKey:portal`）。
2. 每个请求显式 `Cookie` 头：名值对按名称排序、`"; "` 拼接（`SchoolCookies.headerValue` 已实现并测试）。
3. 每个响应解析 `Set-Cookie`（只取 name=value）合并回字典（`SchoolCookies.mergeSetCookie` 已实现并测试）。
4. 会话失效或退出时清空字典，但保留本地身份以便离线读取缓存。
5. Android 登录前使用进程内匿名 Cookie 字典保存验证码会话；认证成功前不写入 Keystore，成功后整体迁移到身份作用域。

### 登录流程

**本科：**
1. `GET {base}/Logon.do?method=logon&flag=sess` → 明文 body = 登录 key，`#` 分割为 `secretCode#secretKey`。前置 `clearCookies()`。
2. `GET {base}/verifycode.servlet` → 验证码图片。
3. `POST {base}/Logon.do?method=logon`，`application/x-www-form-urlencoded`，字段：`useDogCode=`（空）、`encoded=<encodeKey(key, account, password)>`、`RANDOMCODE=<验证码>`（trim）。
   `encoded` 算法：`code = account + "%%%" + password`；对 `i < 20 && i < secretKey.length`：追加 `code[i]`，然后追加 `secretKey[i]` 指向的 `secretCode` 前 N 个字符并删除之；之后追加剩余 code。
4. 成功判定：`isAuthenticatedResponse`（URL/HTML 标记，见下）且会话校验通过，或会话校验单独通过。失败取 `extractLoginMessage`（`alert('…')`/`showMsg('…')`/`<font color='red'>…</font>`，忽略「请输入完整的登陆信息」等两条）。
5. 会话校验：`GET {base}/jsxsd/framework/xsMain.jsp`，失败重试 2 次、间隔 300ms。

**研究生：**
1. `GET {gradBase}/home/stulogin` → HTML 中 `#pubkey` 的 `value` 为 RSA 公钥。缺失即失败。
2. `GET {gradBase}/home/verificationcode?codetype=stucode`（referer `/home/stulogin`）→ 验证码。
3. `POST {gradBase}/home/stulogin_do`，`application/x-www-form-urlencoded; charset=utf-8`，body：`json=<URL 编码 JSON>`，JSON 为 `{"UserId": account, "Password": base64(RSA-PKCS1(password)), "VeriCode": 验证码(数字则 Int), "url": "", "city": ""}`。
4. 响应为 **AES-128-ECB/PKCS7（key `southsoft12345!#`）base64** 密文；`==gwJPTxzG0iY2qTiSUo7wB6` 的 base64 代表 `"-"`。
5. 解密后 JSON：成功 iff `jg == "1"` 且 `url` 非空；否则 `loginFailed(msg)`。
6. 登录后 `POST {gradBase}/student/default/getxscardinfo` 取 `xm` 显示名；响应含 `stulogin`/`</script>` 视为会话过期。

### 页面识别与登录态判定

- `isLoginPage`：含 `Logon.do?method=logon`、`stulogin_do`、`name="RANDOMCODE"`/`name='RANDOMCODE'`、`verifycode.servlet`、`verificationcode`、`pubkey`、`验证码`。
- `isAuthenticatedResponse(url, html)`：登录页→false；URL 含 `xsMain.jsp`、`/jsxsd/framework/`、`/jsxsd/xsks/`、`/jsxsd/xskb/`、`/jsxsd/kscj/`（非 `Logon.do`）→true；HTML 含 `xsMain.jsp`、`退出系统`、`安全退出`、`个人信息`、`学生课表`、`成绩查询`→true。
- 预检 `preflightAuthenticatedSession`：无身份→需重登；最近校验 <5s→已认证；否则本科 GET `xsMain.jsp`、研究生 GET `getxscardinfo`，登录页→清 Cookie 登出→需重登，网络异常→不可达。
- 错误分类：`cannotFindHost/cannotConnectToHost/dnsLookupFailed/networkConnectionLost/notConnectedToInternet/timedOut/…` → `campusNetworkRequired`。

### 数据接口

| 数据 | 请求 | 说明 |
|---|---|---|
| 本科课表 | `GET /jsxsd/xskb/xskb_list.do?xnxq01id=<semesterID>`（referer `Logon.do`）；HTML 表单兜底 `resolveTimetableRequest`（POST 表单字段，优先目标学期） | 学期 ID 来自 `SemesterConfig`（内置 `2025-2026-2`，可被 `semester_runtime_configs` 覆盖） |
| 研究生课表 | `GET /student/pygl/py_kbcx_ew?kblx=xs&termcode=<graduateTimetableTermCode>`（内置 `46`） | 响应 AES-ECB 解密后为 JSON `{"rows":[…]}` |
| 成绩 | `GET /jsxsd/kscj/cjcx_list` | 单页含成绩、排名、学分详情三块 |
| 考试 | `POST /jsxsd/xsks/xsksap_list`（`xqlbmc=` 空、`xnxqid=<学期>`、`xqlb=` 空） | GET 候选 `/xsksap_list`、`/xsksap_query`、`/xskscx_list`、`/xskscx_query` |
| 教学计划 | `GET /jsxsd/pyfa/pyfa_query` | referer `xsMain.jsp` |
| 毕业要求 | `GET /jsxsd/pyfa/pyfazd_query` | 同左 |
| 排名 | `GET /jsxsd/kscj/cjcx_list` 后，候选 `cjpm_query/cjpm_list/cjpmcx_query/cjpmcx_list/cjcx_pm` | — |
| 空教室 | `GET /jsxsd/kbxx/jsjy_query2`，参数 `xnxqh/zc/zc2/jc/jc2/xq/xq2/jszt=5` 等 | 周/天由学期首日推算 |
| 教室占用 | 每节次 1 个请求（节次 1-12），12 并行 | — |
| 校历资源 | `GET /images/xiaoli.jpg`、`/images/schooltime.jpg` | — |

### 编码与解析

- 解码：优先 UTF-8，失败回退 **GB18030**，再失败报 `cannotDecodeRawData`。Android 侧需复刻（OkHttp 拿到 bytes 后自行解码）。
- 研究生课表/登录响应为 AES-ECB 密文 → 明文 UTF-8。
- 选择器清单（SwiftSoup ↔ jsoup 一致）：`[id^=kbcontent_]`、`.kbcontent`、`#kbtable`、`#dataList`、`table.Nsb_r_list`、`tr/td/th`、`p`、`a[href]`、`select[name=xnxq01id]`、`input[name=xnxq01id]`。`parseStudentBlock` 需直接遍历节点树（TextNode / `<br>` / `<hr>`）。
- 可信空 vs 不可解析：`kbcontent` 内容元素全部无文本→可信空；有文本但解析不出→`tableRowsUnparseable`；无目标结构→`tableNotFound`。成绩表头识别（含「课程名称/成绩/学分」）后空表→可信空。
- 研究生课表：`rows` 为空→可信空；`rows` 非空但 0 条→不可解析。`mc` 列正则 `\d+` 取节次，`z<day>` 列取每天课程。

### WebView 兜底

`TimetableWebViewBootstrapper`：非持久化 WKWebView、注入 Chrome UA 与持久化 Cookie；先载 `xskb_list.do`（等 1.2s），失败载 `xsMain.jsp`（等 0.8s）后点击「培养管理」→「本人课表/学生课表/学期理论课表」（等 1s）；JS 捕获含 `id="kbtable"|kbcontent_|class="kbcontent"` 的 iframe 内容。Android 对应隐藏 WebView + Cookie 注入 + `evaluateJavascript`。

## Supabase 客户端契约

Android **不新建后端**，继续使用现有 Supabase。阶段 2 建立客户端层：`SupabaseConfig`（已就位）→ supabase-kt。

### 客户端调用的 Edge Functions（HTTP）

`community-bootstrap-user`（POST，body `{edu_id, display_name, campus_id}`，返回 `{profile, is_new_user, is_profile_complete}`）、`community-feed`（GET，`limit/campus_id/mode=hot/category/search`）、`campus-weather`（GET）、`community-validate-upload`、`community-validate-attachment`、`community-attachment-download`、`community-delete-account`、`campus-request`。均带 `Authorization: Bearer <accessToken>`（函数 `verify_jwt=false`，自行验证）。

### 客户端调用的 RPC（PostgREST）

`backend_capabilities_v1`（能力清单，缓存）、`community_campuses_v1`、`community_profile_stats_v1`、`create_community_post_v4`、`attach_community_post_image_v1`、`attach_community_post_attachment_v1`、`abort_community_post_upload_v1`、`create_community_comment_v2(_idempotent)`、`list_community_comment_threads_v1`、`toggle_post_like_v1`、`toggle_community_comment_like_v1`、`toggle_post_favorite_v1`、`soft_delete_own_post/comment`、`accept/revoke_community_terms`、`create/accept/revoke/stop/leave_timetable_share` 系列、`current_campus_membership_request`/`select_community_campus`/`submit_*`。

### 认证

学校登录成功 → **匿名 Supabase Auth**（`signInAnonymously`，iOS 12s 超时、25s 总看门狗）→ `community-bootstrap-user` 按 `(campus_id, edu_id)` 建立/继承 profile。一个 `(campus_id, edu_id)` 一个长期 profile；多设备匿名会话自动继承同一 profile。

### 存储

三个私有 bucket：`community-images`（JPEG，帖子图/头像/封面）、`community-attachments`（pdf/docx/xlsx/md ≤10MB）、`community-banner-assets`（运营 banner）。图片经 `community-validate-upload` 验证（≤1600px/缩略图 480px），附件 magic bytes 校验；下载走 `community-attachment-download` 短期签名 URL。

### RLS 要点

身份经 `current_profile_id()`（profile_auth_links 映射）；读写要求 campus 作用域（`campus_id = current_profile_campus_id()`）与 ownership（`can_use_profile`）+ 完整资料/社区准入。变更类操作走 security definer RPC，直写授权被移除。`semester_runtime_configs` 对 anon/authenticated 仅读 `is_active` 行。

## 安全边界

- Git 提交禁止：Supabase service_role、release keystore/密码、私有证书、真实账号密码、教务密码、production secret。
- Android 仅持有公开 anon key（`secrets.properties`，git-ignore；示例见 `secrets.properties.example`）。
- 教务 Cookie 与登录凭据经 Keystore AES-GCM 加密落盘（`SecureStorage`）。
- 日志默认脱敏：不记录密码、Cookie、验证码、完整 token；网络调试留存 HTML 快照需脱敏（学号、长数字串）。

## 发布预留

Gradle 已预留 `versionCode / versionName / applicationId / signingConfig（release）`。阶段 1 不写真实 key；未来流程：Git Tag → GitHub Actions → Gradle Release Build → APK Signing → GitHub Release。

## 后续阶段路线

- **阶段 2 教务接入（M2.1-M2.5）：已完成。** OkHttp 客户端（登录/Cookie/编码）、jsoup 解析器与 Fixture 回归、Room 落库、课表网格渲染、登录页、成绩/考试抓取与展示。
- **阶段 4 社区核心体验：已完成。** supabase-kt（匿名 Auth + bootstrap + feed）、帖子详情/评论/点赞、文本发帖与评论、搜索、分类/热门、通知、收藏、本人内容软删除、举报和屏蔽。
- **阶段 5 校园与我的：核心闭环已完成。** 空教室、成绩/排名与考试独立同步、领域分组；社区资料 bootstrap 与昵称/简介/专业/年级编辑；主题/文字偏好、缓存与单项同步中心、安全退出、帮助/权限/反馈/关于。评价目录、共享课表成员与邀请码留到后续阶段。
- **阶段 3 日迹基础闭环：已完成。** 随记编辑/软删除、个人日程增删改、课表共享数据源与 ICS；复杂 Markdown、图片/语音、统计和分享卡片留到增强阶段。
- **UI 后续收尾**：逐步把 `FeatureDestination` 占位替换为真实实现；校园网依赖页面单独做真机/可访问教务网络验收，静态说明页保持可离线使用。
- **发布工程**：WorkManager 后台刷新、Widget（Glance）、通知、release 签名与 CI。

每阶段验收：`./gradlew assembleDebug` 通过；能单测的纯逻辑加测试；行为/边界变化同步更新本文、`state/` 与 `contracts/`。
