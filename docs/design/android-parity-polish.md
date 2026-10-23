# Android 与 iOS 对齐优化

日期：2026-10-23。范围：Android 客户端；iOS 仅作为行为与视觉参照，未修改任何 iOS 代码。

本轮不新增产品能力、不改变请求范围。目标是把 Android 的账号密码链路、课表拉取过程、视觉层次和几处数据正确性问题收敛到当前 iOS 的契约。

## 账号密码

- 备份规则排除 `myleafy_secure_store.xml`。Keystore 密钥不随 Auto Backup 迁移，密文也不应进入云端；换机恢复按“需要重新登录”处理。
- `SecureStorage` 区分 `Missing / Found / Unreadable`；解密失败删除坏条目并记录日志，不再伪装成首次使用。
- 凭据保存、删除和登出使用 `commit()`，返回前校验落盘；新生成的 Keystore key 请求 `setUnlockedDeviceRequired`，不支持的设备回退并记录告警。
- 修改学号时清空预填密码；登录成功以会话建立为准，自动填充/本机身份保存失败只记录告警，不回滚登录。
- 学号/密码字段向系统 Autofill 暴露 username/password 语义；验证码在首次进入、回前台、网络恢复时按 2 秒节流重试。
- 登录表单改为单卡分组（24dp、1px 分隔线），错误只在存在时占位，网络/SSL/业务错误分别给出可读文案。

## 课表拉取

- 学校可信空结果且本地已有课程时保留本地课表与个人数据，结果文案明确说明“已保留”；只有本地原本为空才写入空结果。
- 用户主动刷新使用步骤列表（运行/完成/失败原因），不再用一行弹窗覆盖历史；首次同步复用同一模型，认证恢复作为当前步骤的 detail。
- 下拉刷新指示器改为覆盖层，不参与 Column 测量；移除“先进度条、后模态框”的两套表达。
- 课前提醒协调移到后台线程，先持久化新 ID 集合，只取消本次不存在的闹钟；单条失败累计报告，不再中断其余项。闹钟 ID 纳入提前分钟数。
- 教务 OkHttp 请求改用可取消的 suspend 桥（与 `BackendClient` 相同模式），切身份/退出页面时立即取消连接。

## 视觉

- 内容卡统一 `MaterialTheme.shapes.large`（24dp）+ 1px `cardBorder` + 浅色模式 2dp 投影；深色模式靠描边维持层级。
- 根页面绘制一次 accent 5–8% 主题渐变；顶部栏透明，滚动后使用 94% elevated。
- 课程块 12dp，1px 描边，浅色 1dp 投影，今日使用 primary 描边；空白格改为很淡的内容表面。
- 课程色改为同一品牌基色按白度/暗度递进；中性 surface 统一为绿灰色族；关闭 `surfaceTint` 的 elevation 染色。
- 新增 `LeafyAlpha` / `LeafyStroke` 语义 token，替换 0.12/0.35/0.45/0.55 等散落 alpha；暗色 modal 与 card 分离。

## 数据与流程

- 评论线程完整回传 `after_created_at` / `after_id`，支持继续加载；评论作者与回复对象使用服务端 `author` / `reply_to_author`。
- 评论发送只刷新评论页，不再整页 Loading；点赞/收藏在 await 后读取最新状态。
- Feed 增加进程内按身份/校园/筛选的缓存，一分钟内返回不重复刷新；刷新按已加载深度取回。
- 通知协调先按稳定 work name 覆盖入队，再清理过期 work，消除“零提醒”窗口。
- 日迹标签/统计/回顾/回收站读取失败保留最近成功列表并显示错误；正文 `#标签` 在保存时合并。
- 删除日程级联删除提醒行；图片压缩在质量到底后继续按 0.82 缩尺寸。
- 课程详情改为可传入窄依赖，不再在组合体内直接 cast Application。

## 工程

- release 开启 R8 与资源压缩，补充 kotlinx.serialization / Room / WorkManager 规则。
- CI 增加 `compileReleaseKotlin`、`lintRelease`，以及独立的 instrumented job（API 35 emulator）运行 `connectedDebugAndroidTest`。
- 删除从未被读取的 `themeColor` / `language` 设置键。

## 验证与边界

- JVM：186 项，179 通过、7 项外部探测跳过，0 失败。
- lint：0 error（Debug）。
- Roborazzi：73 张基线重录并 verify 通过；已人工查看登录浅/深、200% 字体、课表浅/深、社区、我的、校园等代表图。
- `assembleDebug`、`assembleDebugAndroidTest`、`compileReleaseKotlin`、R8 `assembleRelease`（临时测试签名）通过。
- isolated API 36 模拟器 instrumented 47 项全部通过（两次导航基线断言已改为不依赖设备像素密度与渐变逐通道相等）。CI instrumented job 尚未在远端首次执行。
- 未做真机 instrumented、Release 帧时、baseline profile 或与 iOS 同期性能对照；这些仍需独立设备与测量，不能由本轮构建结果推导。
