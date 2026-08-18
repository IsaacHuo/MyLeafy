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
| 结构 | 单 `:app` module；本地 Room 库 `myleafy.db` |
| 验证 | `./gradlew :app:assembleDebug` ✓；`./gradlew :app:testDebugUnitTest` ✓（9 用例） |

阶段 1 交付：可编译、可运行、5 Tab 可导航、架构（Compose → ViewModel → Repository → DataSource）正确的工程骨架。

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

- 课表投影（`TimetableGridSnapshot` / `WeeklyTimetableProjection` / 重叠课程布局）→ Compose `LazyLayout` 自绘网格 + 预计算投影。
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

**阶段 1 已接入：** compose（ui/material3/icons-extended）、navigation-compose、lifecycle（runtime/viewmodel-compose）、activity-compose、core-ktx、room（runtime/ktx/compiler via KSP）、junit（测试）。

**版本目录已锁定、阶段 2 按需接入：** okhttp 5.5.0、jsoup 1.23.1。

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
        ├── AndroidManifest.xml        # 含 network-security-config（两教务域明文）
        ├── res/                       # 字符串、主题、自适应启动图标
        └── java/com/myleafy/android/
            ├── MyLeafyApplication.kt / MainActivity.kt
            ├── ui/theme/              # M3 亮/暗，鼠尾草绿
            ├── ui/MyLeafyApp.kt / ui/components/
            ├── navigation/            # RootTab + MyLeafyNavHost（5 Tab 固定）
            ├── features/
            │   ├── auth/              # 登录仓储 + ViewModel + 占位页
            │   ├── timetable/         # Room 数据链路已验证 + 占位页
            │   ├── community/         # 仓储接口 + ViewModel + 占位页
            │   ├── schedule/ campus/ profile/  # ViewModel + 占位页
            ├── core/
            │   ├── campus/            # CampusID/Capability/Descriptor/ActiveCampusContext
            │   ├── data/local/        # Room：CourseEntity + CourseDao + AppDatabase
            │   ├── di/                # AppContainer + appViewModelFactory
            │   ├── network/           # 教务客户端接口/Cookie 契约/错误/身份 scopeKey
            │   ├── security/          # SecureStorage（Keystore AES-GCM）+ 凭据/Cookie 存储
            ├── parsers/               # HtmlParser 接口 + 解析结果类型
            └── services/              # SupabaseConfig（BuildConfig ← secrets.properties）
```

### 架构决策

- 依赖方向固定：`Compose UI → ViewModel → Repository → DataSource`；无 UseCase 泛滥、无 Base 类。
- 阶段 1 固定 5 Tab（课表/社区/日迹/校园/我的），不做 capability 门控；社区门控逻辑保留在 `CampusDescriptor`，后续接入。
- `CourseEntity` 已映射并在课表页展示「本地缓存课程数」，验证 Room 全链路可编译运行。
- Room 早期采用 `fallbackToDestructiveMigration(dropAllTables = true)`；正式发布前改为受控 migration。

## 数据模型映射表（DTO / Entity）

「Swift Type / Android Type / 关键字段 / 本地持久化 / 跨平台共享」详见下表。**纯 UI 投影不进入 Android 数据模型**（如 `TimetableGridSnapshot`、`WeeklyTimetableProjection`、`GradeAnalytics`、`ScheduleMemoStatistics`）。

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

1. **阶段 2 教务接入**：OkHttp 客户端（登录/Cookie/编码）、jsoup 解析器与 Fixture 回归、Room 落库、课表网格渲染、登录页。
2. **阶段 3 日迹**：随记/日程 Room 模型、Markdown 编辑、统计、分享。
3. **阶段 4 社区**：supabase-kt、匿名 Auth + bootstrap、Feed/详情/发布/通知/投票。
4. **阶段 5 校园与我的**：成绩/考试/空教室、评价目录、个人资料、共享课表。
5. **发布工程**：WorkManager 后台刷新、Widget（Glance）、通知、release 签名与 CI。

每阶段验收：`./gradlew assembleDebug` 通过；能单测的纯逻辑加测试；行为/边界变化同步更新本文、`state/` 与 `contracts/`。
