# Current State

Last verified: 2026-09-05

## Current Focus

- **Android 核心体验对齐**：品牌/身份、课表/个人日程、社区、校园与“我的”核心闭环已完成；Android 1.0.1 登录/社区网络提示热修复已正式发布，并在 Xiaomi 24069RA21C / Android 16 保留身份与本地数据完成覆盖安装、冷启动及社区加载验收。
- **日迹（Schedule）体验收尾**：随记/个人日程/推送三段根入口、记录日迹（自然年统计、近 30 天热力、里程碑）、Markdown 编辑与投稿、本机语音转写与统计分享图。
- **国际化收尾**：已完成英文本地化并加入 App 内语言偏好（跟随系统 / 简体中文 / English，同步到 Widget 与 Share 扩展）；正在打磨英文课表与校园文案。
- **课表与时间语义**：`2026-2027-1` 已作为最新拉取学期，首周仍为 9 月 7 日；按学年浏览、20 周单学期数据集、学年边界滑动与刷新反馈，历史春季课表和暑假可从时间视图按周回看。
- **课表三日缩放与新学期**：周视图使用同一棵 21 日日期列连续形变到三日分页；本周以今天居中，其他周从周一至周三进入，缩回当前三日页所属周。时间视图在暑假提前展示 2026–2027 第一学期及自然顺序 1–12 月缩略。
- **工程收敛**：Presentation → Application → Domain → Data 分层重构，移除已被当前实现取代的兼容入口与旧类型。

## Recently Completed

- **Android 第二轮 UI 精修与截图基线**：在首轮 Design System 上补充 progress、刷新阈值、空状态宽度及课表/校园/登录功能级 Token；课表日期/今天/当前时间层级、社区平坦信息流、日迹轻量 Tab、校园宽屏侧栏、“我的”设置分组与登录 IME 流程完成第二轮收敛，业务状态机、RootTab、路由和 capability 门控保持不变。Roborazzi 1.56.0 + Robolectric 4.16 以独立 JUnit category 管理中文/上海时区 golden，CI 只验证并上传差异。修复课表照片背景退出/切换时 UI 层提前回收 Bitmap 导致的 `Canvas: trying to use a recycled bitmap` 崩溃，并加入 instrumentation 生命周期回归测试。
- **Android 对照式 UI 精修**：Compose Design System 补齐系统字体 Typography、Spacing、Elevation、IconSize、Motion、Surface 与课程色板，浅深色 Material 3 语义角色不再回落默认紫色；根导航接入官方 Adaptive Navigation Suite，Compact 使用 Bottom Navigation、Medium/Expanded 使用 Navigation Rail，保持 `RootTab`、状态恢复、深链和 capability 门控不变。课表、社区、日迹、校园、“我的”、登录及已实现二级页已迁移到统一 TopBar、Surface、状态组件、Sheet 与 48dp 触控基线，减少 Card 套 Card 和零散视觉常量。
- **Android 原生能力补全**：课表以 20 页 `HorizontalPager` 横滑切周并保持 13 节单屏无纵向滚动，支持隐藏周末、粗略位置天气和本机照片/纯色背景；社区入口在所有身份下可见但实际请求继续受 capability 门控；日迹默认日程并以 WorkManager 提供早晚报、考试和个人日程提醒；校园加入本机体育/体测/医疗台账及 Supabase 评价目录；共享课表沿用既有一次性邀请码、RLS 和隐私字段白名单。

- **免登录入口（guest）**：登录页新增「免登录入口」，无账号密码、数据全部存本机、不连接任何后台（跳过学期配置远程拉取与社区后台任务）；社区入口仍可见但只展示登录/校园支持说明。行为与通用学校入口一致（本地导入课表/成绩/考试，学期用内置 1–20 周默认容器）。登录页与校园描述中「通用入口」改名为「通用学校入口」。
- **教务会话渐进恢复**：用户主动更新课表、成绩、考试、教学计划、培养方案和空闲教室时优先复用现有 Session；本科 Session 明确过期后最多刷新并识别三张验证码，每张使用原图、放大、灰度增强三路 Vision 共识，OCR 不可靠或学校明确返回验证码错误时继续下一轮，第三轮后转人工；账号密码、未知错误或校园网不可达立即停止，研究生端保持人工验证码恢复。
- **教务操作过程反馈**：用户主动同步时按实际范围展示连接、验证码识别、登录验证及数据拉取/处理/保存步骤；课表、成绩、全量、教学与培养、考试、排名和教室查询互不扩大请求范围，后台预取保持静默。
- **Android 工程骨架（阶段 1 / 1.5）**：`android/` 为可编译可运行的 Compose 单模块工程（Gradle 8.14.5 / AGP 8.13.2 / Kotlin 2.2.21 / minSdk 29）；根 Tab 真实导航，全功能基础架构已搭好（UiState 状态机 / Repository / Room v5 / DTO / DataStore / 登录路由 / 深链），日迹为真实可用的本地 CRUD，数据库提供显式 4→5 migration。
- **Android 对齐基础层**：启动图标从 iOS 唯一母版生成 legacy/adaptive/monochrome 资源；Compose 使用 12/16/24dp 品牌圆角层级；`ActiveAppScope` 统一校园身份、capability 与 Room `scopeKey`，所有本地表和 DAO 已按身份隔离，guest/无社区能力身份不会初始化 Supabase；新增 Android assemble/JVM tests/lint CI。
- **Android 课表与日程对齐**：稳定 Compose `Layout` 渲染 5/7 天 × 13 节单屏网格，`TimetableGridProjection` 预计算课程/考试/个人日程跨度与冲突 lane，`HorizontalPager` 预投影相邻周真实内容；“回到本周/同步”收入口菜单。课表和日迹共用 scoped Room 日程，支持新增、编辑、删除、重启持久化；所选学期课程与范围内个人日程可按 `Asia/Shanghai` 导出 RFC 5545 ICS，并通过 FileProvider/系统 Sharesheet 分享。
- **Android 社区核心体验对齐**：真实 Feed 支持分类、近七日热门、稳定下拉刷新和失败保留最近成功内容；搜索与通知不再是占位页，通知包含未读数、单条/全部已读和帖子导航。详情补齐收藏、本人帖子/评论软删除、举报与屏蔽确认，所有操作继续走现有 Supabase RLS / Edge Function / RPC 契约；自定义校园准入和资料完整度在仓储边界统一校验。
- **Android 校园与“我的”对齐**：校园工具按学校教学/自习安排/体育相关/医疗事项/评价相关分组，成绩/排名与考试支持互不扩大的单项同步，空闲教室结果可在窄屏滚动；社区资料可编辑昵称、简介、专业和年级。DataStore 主题、文字、隐藏周末与课表背景偏好即时应用；共享课表、背景、帮助、权限、反馈与关于均为真实入口。退出登录清理学校 Cookie、保存凭据与 Supabase 匿名会话，但保留对应身份的 scoped Room 数据。
- **Android 发布加固**：Android 版本升级为 1.0.0；release task 缺少独立签名或 Supabase 公开配置时直接失败。`Cut Android Release` 会执行 JVM tests、lint 和 signed assemble，使用 `apksigner` 校验后发布 APK、SHA-256 与源码 commit/签名报告；Android tag 使用独立的 `android-vX.Y.Z` 命名，不改变 iOS `vX.Y` 发布流程。
- **Android 1.0.0 正式发布**：2026-08-31 从源码 `24da9e18d36a3a8b759c368700f79553a39a2f08` 发布 immutable tag `android-v1.0.0`；Release 包含签名 APK、SHA-256 和构建信息，下载后复核包名、版本、源码 commit、文件散列及发布证书均一致。Android Release 不包含 iOS 二进制。
- **Android 1.0.0 小米真机验收**：Release APK 已安装到 Xiaomi 24069RA21C（Android 16），系统报告 `com.myleafy.android` / versionCode 1 / versionName 1.0.0；`MainActivity` 启动成功、进程存活且课表根页完整渲染。未绑定学校身份时按 capability 隐藏社区，登录学校账号后显示五个根 Tab。
- **Android 阶段 2（教务，M2.1-M2.5）**：OkHttp 教务客户端 + Cookie 契约、强智登录（encodeKey/验证码/会话验证）、课表抓取 + jsoup 解析（contracts fixtures 回归）+ Room 落库、周课表网格、成绩/考试抓取与校园页。
- **Android 阶段 4（社区）**：supabase-kt（匿名 Auth + bootstrap + feed）、帖子详情/评论线程/点赞、文本发帖与评论，以及搜索、分类/热门、通知、收藏、本人内容软删除、举报和屏蔽。
- **Android 阶段 5 部分（M5.1-M5.2）**：我的页社区资料（bootstrap）、空闲教室查询。
- **Android UI 壳收敛**：底栏只显示在 5 个根页面，常用二级功能由 `FeatureDestination` 统一路由；帮助中心、权限说明、关于与内置校历已完成静态内容，页面不注入演示数据，日迹空库仍可创建第一条随记。
- **Android API 36 设备验收**：`MyLeafy_API_36`（Pixel 8 / Android 16）已通过既有 instrumentation 用例（根导航、scoped Room 重开、课表/日程与社区 Compose 交互）；真实旅程验证个人日程保存、强制结束后持久化、日迹共享数据源和 ICS Sharesheet。guest 模式保持五个根入口，社区内容与 Supabase 初始化仍按 capability 隔离。
- **Android 本科登录实测修复**：登录前验证码会话 Cookie 以内存态跨 key/验证码/提交复用，认证成功后才迁移到 Keystore；所有同步 OkHttp 教务入口改在 `Dispatchers.IO` 执行。2026-08-29 已用真实校园网络完成验证码和登录验证。
- **Android 1.0.1 登录与社区网络提示热修复**：登录失败原因和验证码加载错误分开持有，自动刷新验证码不再清空学校返回的失败原因。真机确认 `bjfu-wifi` 会为 Supabase 连接返回 `*.bjfu.edu.cn` 证书；客户端继续拒绝主机名不匹配，并改为提示切换网络或检查代理/VPN。切换网络后同一身份的社区 Feed 已恢复。1.0.1 已从源码 `ad7915c7f71278c9c10e8320c2f959c8cbd9aa91` 发布并覆盖安装到小米真机，调查记录见 `logs/2026-08-31-android-campus-wifi-tls-interception.md`。
- 教务网络（研究生 RSA/AES）与 Android Widget 仍待接入；共享课表、评价目录和 WorkManager 日迹通知已接入。Android 1.0.0 已发布并完成小米真机安装验收。迁移方案与教务协议记录见 `docs/engineering/android-migration.md`，解析回归样本见 `contracts/jwxt/`。iOS 代码未改动。
- 教务全量同步区分完整成功、部分成功与失败；课表、成绩、考试、教学计划与空闲教室只在确认目标结构或可信空结果后更新缓存，异常页面继续保留最近成功数据。
- 社区投票局部错误、帖子/评论重试幂等、日迹长列表投影、Dynamic Type、VoiceOver 与核心英文文案完成一轮可靠性收敛。
- iOS 社区 Feed 在活跃 Tab 内订阅校园范围的帖子/投票变更并后台预取；新内容由顶部入口显式应用，下拉刷新区分更新、最新、空结果、部分失败与失败。
- 2.9 正式发布（build 27，App Store 2026-08-03，tag `v2.9`）。
- 完整英文本地化 + App 内语言偏好基础设施。
- 随记 Markdown 编辑与投稿能力升级。
- 课表学年边界滑动与刷新反馈改进。
- 课表三日非重叠分页重构为单布局、可中断、速度感知的连续缩放；手势帧只更新几何状态，数据窗口在交互期间冻结。教师评价跳转、背景照片即时替换、投票比例常显和第一学期阳光长跑周期完成。
- 新建个人日程以同一条记录同时呈现在日程列表和随记流；旧日程不补写创建时间。
- 分层重构并移除过时兼容（commit `cad654d`）。
- 删除 MyLeafy AI 公开实现与商品配置（不再有相关代码）。
- 记录日迹、自习安排重组（专注记录归入学习空间）等功能完成。

## In Progress

- **Cloudflare 后台迁移**：迁移分支已实现 Worker/D1/R2 的部分业务、认证、媒体与迁移工具，并部署 staging 完成首轮合成数据冒烟。生产仍使用 Supabase；iOS 新传输层尚未接入页面，Android/管理端/分享页及完整反向恢复尚待完成。生产 Data API 和 CLI 数据库连接当前超时，真实数据与文件未迁移。实施边界和操作步骤见 `docs/engineering/cloudflare-migration.md`。

- 未发布版本（见 `docs/operations/release-notes.md` “未发布”一节）：
  - 日迹卡片白色系统表面、Tag 白字主题色胶囊与“全部随记”筛选；
  - 记录日迹本机统计分享图（仅聚合数据）；
  - 随记输入器聚焦展开与长文本放大编辑；
  - 编辑资料和“我的”主页隐藏竖向滚动指示器。
- 英文课表与校园文案润色、本地化目录规整。

## Known Problems

- **教务系统不稳定**：HTML、登录流程或网络策略变化可能使解析暂时失效（持续风险，见 `docs/product/overview.md` §7）。
- **Android 本科课表结构变化**：真实登录后的 `xskb_list.do` 当前返回 `200`，但页面不含 Android 解析器支持的 `kbcontent/kbtable` 结构，App 会如实报“课表数据不可用”并保留缓存；后续需迁移 iOS 的表单解析 / WebView bootstrap 回退。
- **模拟器与全局代理**：Clash 等全局代理可能接管模拟器 NAT，使教务 HTTP 返回 `502`，而宿主机直连仍为 `200`；验收时需为学校域名/IP 配置直连，不能在 App 中硬编码个人代理。
- **校园 Wi-Fi TLS 拦截**：2026-08-31 真机确认 `bjfu-wifi` 对 Supabase HTTPS 连接返回校园域名证书，Android 必须拒绝该连接；切换网络后社区恢复。不得通过关闭 TLS 主机名校验绕过，详见 `logs/2026-08-31-android-campus-wifi-tls-interception.md`。
- **身份绑定强度**：教务身份由已修改的客户端提交，服务端无法独立证明来源；高价值权益需要可信服务端验证。
- **目录数据依赖人工维护**：教师/课程等目录需模板导入或后台审核。
- **MyLeafy AI 已移除**：历史审核复盘（`docs/operations/app-store/2.9-build-22-review.md`）中的 AI 相关描述不代表当前产品。

## Next

按 `docs/product/roadmap.md` 的近期重点推进，不承诺固定时间表：

- 在可访问学校环境中单独验收登录、教务同步及社区 capability 旅程。
- 提高教务解析稳定性与解析回归测试覆盖。
- 统一不同校园的数据适配协议与能力配置。
- 连接课表、日程与学习空间的时间语义。
- 收紧身份绑定、共享、导出与管理操作的安全边界。
- 架构或主要功能状态变化后，同步更新本文件和 `state/ARCHITECTURE.md`。
