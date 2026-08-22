# Current State

Last verified: 2026-08-22

## Current Focus

- **日迹（Schedule）体验收尾**：随记/个人日程/推送三段根入口、记录日迹（自然年统计、近 30 天热力、里程碑）、Markdown 编辑与投稿、本机语音转写与统计分享图。
- **国际化收尾**：已完成英文本地化并加入 App 内语言偏好（跟随系统 / 简体中文 / English，同步到 Widget 与 Share 扩展）；正在打磨英文课表与校园文案。
- **课表与时间语义**：按学年浏览（秋季开学至下一学年开始前一天）、20 周单学期数据集、学年边界滑动与刷新反馈。
- **课表近三日与新学期**：周视图可双指切换到昨天/今天/明天，时间视图在暑假提前展示 2026–2027 第一学期及 9 月至次年 1 月缩略。
- **工程收敛**：Presentation → Application → Domain → Data 分层重构，移除已被当前实现取代的兼容入口与旧类型。

## Recently Completed

- **Android 工程骨架（阶段 1 / 1.5）**：`android/` 为可编译可运行的 Compose 单模块工程（Gradle 8.14.5 / AGP 8.13.2 / Kotlin 2.2.21 / minSdk 29）；5 个根 Tab 真实导航，全功能基础架构已搭好（UiState 状态机 / Repository / Room v2 / DTO / DataStore / 登录路由 / 深链），日迹为真实可用的本地 CRUD。
- **Android 阶段 2（教务，M2.1-M2.5）**：OkHttp 教务客户端 + Cookie 契约、强智登录（encodeKey/验证码/会话验证）、课表抓取 + jsoup 解析（contracts fixtures 回归）+ Room 落库、周课表网格、成绩/考试抓取与校园页。
- **Android 阶段 4（社区，M4.1-M4.3）**：supabase-kt（匿名 Auth + bootstrap + feed）、帖子详情/评论线程/点赞、文本发帖与评论。
- **Android 阶段 5 部分（M5.1-M5.2）**：我的页社区资料（bootstrap）、空闲教室查询。
- 教务网络（研究生 RSA/AES）与部分校园工具（共享课表、评价目录）、日迹强化、发布工程（Widget/WorkManager/签名）仍待接入。迁移方案与教务协议记录见 `docs/engineering/android-migration.md`，解析回归样本见 `contracts/jwxt/`。iOS 代码未改动。
- 教务全量同步区分完整成功、部分成功与失败；课表、成绩、考试、教学计划与空闲教室只在确认目标结构或可信空结果后更新缓存，异常页面继续保留最近成功数据。
- 社区投票局部错误、帖子/评论重试幂等、日迹长列表投影、Dynamic Type、VoiceOver 与核心英文文案完成一轮可靠性收敛。
- 2.9 正式发布（build 27，App Store 2026-08-03，tag `v2.9`）。
- 完整英文本地化 + App 内语言偏好基础设施。
- 随记 Markdown 编辑与投稿能力升级。
- 课表学年边界滑动与刷新反馈改进。
- 课表三日放大、教师评价跳转、背景照片即时替换、投票比例常显和第一学期阳光长跑周期完成。
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
- **身份绑定强度**：教务身份由已修改的客户端提交，服务端无法独立证明来源；高价值权益需要可信服务端验证。
- **目录数据依赖人工维护**：教师/课程等目录需模板导入或后台审核。
- **MyLeafy AI 已移除**：历史审核复盘（`docs/operations/app-store/2.9-build-22-review.md`）中的 AI 相关描述不代表当前产品。

## Next

按 `docs/product/roadmap.md` 的近期重点推进，不承诺固定时间表：

- 按 `docs/engineering/android-migration.md` 推进 Android 阶段 2：教务网络层（OkHttp + Cookie + 编码）、jsoup 解析器与 Fixture 回归、课表网格渲染、登录页。
- 提高教务解析稳定性与解析回归测试覆盖。
- 统一不同校园的数据适配协议与能力配置。
- 连接课表、日程与学习空间的时间语义。
- 收紧身份绑定、共享、导出与管理操作的安全边界。
- 架构或主要功能状态变化后，同步更新本文件和 `state/ARCHITECTURE.md`。
