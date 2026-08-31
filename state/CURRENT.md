# Current State

Last verified: 2026-08-31

## Current Focus

- **Android 核心体验对齐**：品牌/身份、课表/个人日程、社区、校园与“我的”核心闭环已完成；Android 1.0.0 release 签名和独立 GitHub Release 工作流已就绪并通过本地签名 APK 验证，下一步发布 `android-v1.0.0` 并安装到小米真机。
- **日迹（Schedule）体验收尾**：随记/个人日程/推送三段根入口、记录日迹（自然年统计、近 30 天热力、里程碑）、Markdown 编辑与投稿、本机语音转写与统计分享图。
- **国际化收尾**：已完成英文本地化并加入 App 内语言偏好（跟随系统 / 简体中文 / English，同步到 Widget 与 Share 扩展）；正在打磨英文课表与校园文案。
- **课表与时间语义**：`2026-2027-1` 已作为最新拉取学期，首周仍为 9 月 7 日；按学年浏览、20 周单学期数据集、学年边界滑动与刷新反馈，历史春季课表和暑假可从时间视图按周回看。
- **课表三日缩放与新学期**：周视图使用同一棵 21 日日期列连续形变到三日分页；本周以今天居中，其他周从周一至周三进入，缩回当前三日页所属周。时间视图在暑假提前展示 2026–2027 第一学期及自然顺序 1–12 月缩略。
- **工程收敛**：Presentation → Application → Domain → Data 分层重构，移除已被当前实现取代的兼容入口与旧类型。

## Recently Completed

- **免登录入口（guest）**：登录页新增「免登录入口」，无账号密码、数据全部存本机、不连接任何后台（跳过学期配置远程拉取与社区后台任务）、无社区 Tab；行为与通用学校入口一致（本地导入课表/成绩/考试，学期用内置 1–20 周默认容器）。登录页与校园描述中「通用入口」改名为「通用学校入口」。
- **教务会话渐进恢复**：用户主动更新课表、成绩、考试、教学计划、培养方案和空闲教室时优先复用现有 Session；本科 Session 明确过期后最多刷新并识别三张验证码，每张使用原图、放大、灰度增强三路 Vision 共识，OCR 不可靠或学校明确返回验证码错误时继续下一轮，第三轮后转人工；账号密码、未知错误或校园网不可达立即停止，研究生端保持人工验证码恢复。
- **教务操作过程反馈**：用户主动同步时按实际范围展示连接、验证码识别、登录验证及数据拉取/处理/保存步骤；课表、成绩、全量、教学与培养、考试、排名和教室查询互不扩大请求范围，后台预取保持静默。
- **Android 工程骨架（阶段 1 / 1.5）**：`android/` 为可编译可运行的 Compose 单模块工程（Gradle 8.14.5 / AGP 8.13.2 / Kotlin 2.2.21 / minSdk 29）；根 Tab 真实导航，全功能基础架构已搭好（UiState 状态机 / Repository / Room v4 / DTO / DataStore / 登录路由 / 深链），日迹为真实可用的本地 CRUD。
- **Android 对齐基础层**：启动图标从 iOS 唯一母版生成 legacy/adaptive/monochrome 资源；Compose 使用 12/16/24dp 品牌圆角层级；`ActiveAppScope` 统一校园身份、capability 与 Room `scopeKey`，所有本地表和 DAO 已按身份隔离，guest/无社区能力身份不会初始化 Supabase；新增 Android assemble/JVM tests/lint CI。
- **Android 课表与日程对齐**：稳定 Compose `Layout` 渲染 7 天 × 13 节圆角网格，`TimetableGridProjection` 预计算课程/考试/个人日程跨度与冲突 lane；周切换保留在紧凑周卡，“回到本周/同步”收入口菜单。课表和日迹共用 scoped Room 日程，支持新增、编辑、删除、重启持久化；所选学期课程与范围内个人日程可按 `Asia/Shanghai` 导出 RFC 5545 ICS，并通过 FileProvider/系统 Sharesheet 分享。
- **Android 社区核心体验对齐**：真实 Feed 支持分类、近七日热门、稳定下拉刷新和失败保留最近成功内容；搜索与通知不再是占位页，通知包含未读数、单条/全部已读和帖子导航。详情补齐收藏、本人帖子/评论软删除、举报与屏蔽确认，所有操作继续走现有 Supabase RLS / Edge Function / RPC 契约；自定义校园准入和资料完整度在仓储边界统一校验。
- **Android 校园与“我的”对齐**：校园工具按学校教学/自习安排/学习空间分组，成绩/排名与考试支持互不扩大的单项同步，空闲教室结果可在窄屏滚动；社区资料可编辑昵称、简介、专业和年级。DataStore 主题与文字偏好即时应用，缓存中心区分教务副本和本机权威数据；退出登录清理学校 Cookie、保存凭据与 Supabase 匿名会话，但保留对应身份的 scoped Room 数据。帮助、权限、反馈与关于均为真实入口。
- **Android 发布加固**：Android 版本升级为 1.0.0；release task 缺少独立签名或 Supabase 公开配置时直接失败。`Cut Android Release` 会执行 JVM tests、lint 和 signed assemble，使用 `apksigner` 校验后发布 APK、SHA-256 与源码 commit/签名报告；Android tag 使用独立的 `android-vX.Y.Z` 命名，不改变 iOS `vX.Y` 发布流程。
- **Android 阶段 2（教务，M2.1-M2.5）**：OkHttp 教务客户端 + Cookie 契约、强智登录（encodeKey/验证码/会话验证）、课表抓取 + jsoup 解析（contracts fixtures 回归）+ Room 落库、周课表网格、成绩/考试抓取与校园页。
- **Android 阶段 4（社区）**：supabase-kt（匿名 Auth + bootstrap + feed）、帖子详情/评论线程/点赞、文本发帖与评论，以及搜索、分类/热门、通知、收藏、本人内容软删除、举报和屏蔽。
- **Android 阶段 5 部分（M5.1-M5.2）**：我的页社区资料（bootstrap）、空闲教室查询。
- **Android UI 壳收敛**：底栏只显示在 5 个根页面，常用二级功能由 `FeatureDestination` 统一路由；帮助中心、权限说明、关于与内置校历已完成静态内容，页面不注入演示数据，日迹空库仍可创建第一条随记。
- **Android API 36 设备验收**：`MyLeafy_API_36`（Pixel 8 / Android 16）已通过 12 个 instrumentation 用例（根导航、scoped Room 重开、课表/日程与社区 Compose 交互）；真实旅程验证个人日程保存、强制结束后持久化、日迹共享数据源和 ICS Sharesheet。guest 模式保持四个本地 Tab，社区仅在校园身份具备 capability 时显示。
- **Android 本科登录实测修复**：登录前验证码会话 Cookie 以内存态跨 key/验证码/提交复用，认证成功后才迁移到 Keystore；所有同步 OkHttp 教务入口改在 `Dispatchers.IO` 执行。2026-08-29 已用真实校园网络完成验证码和登录验证。
- 教务网络（研究生 RSA/AES）与部分校园工具（共享课表、评价目录）、日迹强化、发布工程（Widget/WorkManager）仍待接入；Android GitHub Release APK 和小米真机安装是当前剩余发布动作。迁移方案与教务协议记录见 `docs/engineering/android-migration.md`，解析回归样本见 `contracts/jwxt/`。iOS 代码未改动。
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
- **身份绑定强度**：教务身份由已修改的客户端提交，服务端无法独立证明来源；高价值权益需要可信服务端验证。
- **目录数据依赖人工维护**：教师/课程等目录需模板导入或后台审核。
- **MyLeafy AI 已移除**：历史审核复盘（`docs/operations/app-store/2.9-build-22-review.md`）中的 AI 相关描述不代表当前产品。

## Next

按 `docs/product/roadmap.md` 的近期重点推进，不承诺固定时间表：

- 按 `docs/engineering/android-migration.md` 继续推进 Android 发布加固、签名 APK、GitHub Release 与小米真机安装；校园网依赖能力在可访问学校环境中单独验收。
- 提高教务解析稳定性与解析回归测试覆盖。
- 统一不同校园的数据适配协议与能力配置。
- 连接课表、日程与学习空间的时间语义。
- 收紧身份绑定、共享、导出与管理操作的安全边界。
- 架构或主要功能状态变化后，同步更新本文件和 `state/ARCHITECTURE.md`。
