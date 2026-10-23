# iOS 扩展、Widget 与主题完整审计

本组完整覆盖 28 个文件，其中 20 个 Swift 文件，另有 4 个 plist/entitlements、4 个 xcstrings。包括新增 WidgetWeatherSnapshotTests 和从 Discover 转交的 ExternalLearningMaterialImportTests。逐文件最终 SHA-256、职责、调用/测试、适用规则与证据在 `ios-audit-platform.tsv`。Swift 均完整阅读，资源配置逐项读取并执行结构、格式参数与引用校验。

## 已修复发现

| 编号 | 可复现场景与根因 | 最小修复 | 验证证据 |
| --- | --- | --- | --- |
| PL01 | 多文件共享在后续文件失败时，先前已复制文件留在 App Group；Share 扩展对磁盘/超限/校验等任意 file-representation 错误 try?，错误被 data fallback 改写；不支持或无数据的 provider 还可被静默跳过，形成用户不知情的部分批次 | App 与 Share 扩展在 manifest 提交前失败时统一清理整个 batch；清理失败保留原错误和清理错误，由现有过期清理再次尝试；仅 NSItemProvider 的“无该表示/无法转换表示”允许 data fallback；逐 provider 成功才写入 manifest；动态字号随系统变化 | 新增批次第二文件失败不残留、清理失败可见且之后重试、fallback 信任边界回归；Share 扩展错误文案补 en-US，占位符静态检查通过 |
| PL02 | staged file 的安全作用域开始前就读取元数据，目录可伪装成受支持文件；复制后大小变化、损坏 manifest 的批次 ID/重复资源/负字节/越界路径缺少复核，已提交损坏 manifest 在自动发现时静默消失 | 在 security scope 内读取可抛错的 regular-file 元数据，复制后复核实际大小；manifest 读写检查 ID、唯一性、正大小及限额、支持类型和叶子路径；读取 staged file 再核对所属批次、解析 symlink 后目录和实际大小；pendingManifests 改 throws，未提交的无 manifest 批次跳过，已提交损坏记录向已有 UI catch 报错 | 新增目录拒绝、错 ID/重复/越界/负数、文件变化/symlink、损坏发现回归；Caller 使用 try 交由 Discover 组适配；原 10 文件/25MB/100MB 和类型边界保留 |
| PL03 | Widget 旧单快照文件名和 clear API 没有任何当前生产/测试/配置调用，实际只读写新 archive | 全仓引用检查后移除未用旧常量、旧 URL 与 clear 路径；现有 schema archive、用户选日和发布去重不变 | 全仓符号引用检查、共享源静态解析 |
| PL04 | Widget 温度仍请求旧 Supabase function，而当前工程没有定义任何 SUPABASE_* 构建值，运行只能显示 --°；与 App 当前 WeatherKit 数据源脱节 | 保留温度 UI，删除失效旧请求、重复天气缓存和旧 Info 配置。archive 新增可选 Celsius/observedAt 快照，Widget 仅从已有本机 archive 读取；6 小时到期、未来时间、非有限或 Int 不可表示值显示 --°，未认证不显示；timeline 包含过期边界。root 负责从当前身份 App 天气缓存写入及天气更新重新发布，不新增扩展 WeatherKit entitlement 或网络 | 新增缺字段 archive 解码、过期/坏值、未认证不显示、过期 timeline 四项回归；历史 archive 可正常读取；实际 WeatherKit、App Group 投递和 WidgetKit 刷新仍待设备验收 |

## 保留与边界

- Theme/Chrome 完整核对 iOS 17 与 iOS 26 分支、Dynamic Type、主题精确颜色、item-driven alert、模态环境、44pt 根控件、图库/QuickLook 路由和系统分享。没有按视觉偏好重写布局、调色或动画。
- Widget 保留当天/明天 AppIntent、三种尺寸、本周布局、跨午夜切片、密集重叠详情链接和无障碍描述。签名、系统时间线调度、真实宿主 App 唤起和设备小组件效果不是静态检查的证明范围。
- 资源逐项 JSON/plist 解析通过，Share 所有 literal 本地化键均有对应资源，格式参数在中英文之间匹配；未将未引用旧翻译项当成产品缺陷批量清理。
- 本组执行静态 Swift 解析、资源结构和差异检查；没有构建、启动 Simulator、执行 XCTest、联网调用天气或发布。集中构建/准确提交 CI 由 root 总报告记录。没有宣称 FPS、耗电、内存或延迟改善比例。
