# MyLeafy 发布记录

本文是 MyLeafy 正式版本、源码锚点和用户可见更新摘要的唯一记录入口。App Store 实际使用过的短文案与根据 Git 历史补录的版本摘要分开标注；特定审核过程见 [`app-store/`](app-store/)。正式 tag 创建后不得移动、覆盖或强制更新。

iOS 通过 Xcode 与 App Store Connect 归档、验收和发布。Apple 正式发布后，运行 **Record released iOS version**，核对二进制对应的源码、version/build、main 来源及精确提交 CI，创建不可变 annotated tag 与源码 Release；不构建未签名归档。具体步骤与验收清单见[交付手册](delivery.md)。

Android 使用独立候选准备与管理员验收发布流程，以及 `android-vX.Y.Z` tag。main CI 为新 code 准备私有签名候选；超级管理员验收并授权后发布同一 APK、SHA-256 与构建信息。不因源码合入或候选生成而标为正式发布。

## 当前发行索引

核对日期：2026-10-23（Asia/Shanghai）。GitHub Release/tag、商店和当前源码是不同证据；公开商店查询不能证明内部 build 和源码提交。当前功能差异见 [PLATFORMS](../../state/PLATFORMS.md)。

| 平台 / 版本 | 状态与分发证据 | Build / code | 源码 / tag | 验收边界 |
|---|---|---|---|---|
| iOS 3.2.5 | [中国区 App Store](https://apps.apple.com/cn/app/id6763968535) / [公开查询](https://itunes.apple.com/lookup?id=6763968535&country=cn)，发布时间 2026-10-18 06:49 +08:00 | 待核实 | 待核实；不能从当前 main 推断 | 商店上架已核实；精确二进制、build 与源码对应关系见 [#38](https://github.com/IsaacHuo/MyLeafy/issues/38) |
| iOS 3.0 | GitHub 草稿，不作为正式发行证据 | 待核实 | 草稿 target 为 main，不是确定源码锚点 | 不推断 App Store 交付或测试结果 |
| iOS 2.9 | [正式 GitHub 源码记录](https://github.com/IsaacHuo/MyLeafy/releases/tag/v2.9)，历史记录见下文 | 27（仓库既有 Apple 记录） | `6d5c0331266b49461153fb47b9a17a1f37e5a230` / `v2.9` | 本轮未重新验收历史二进制 |
| Android 1.2.6 | 私有 `android-candidate-10`，未正式发布 | 10 | `592c54b30d84bcd089eecf1034cd53ba10c0b9ce` | 待所有者下载、正式包覆盖升级及管理员授权，见 [#37](https://github.com/IsaacHuo/MyLeafy/issues/37) |
| Android 1.2.4 | [正式 Release 与 APK](https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.2.4)，2026-10-09 | 8 | `c9ff99fd8373a7acc3895a01d835bfbcd7ca5a0c` / `android-v1.2.4` | 正式发布记录已核实；本轮未重做真机验收 |

Android 1.2.4 正式 APK 的 GitHub asset SHA-256 为 `332b5d80aec17d63805e09c7896ba6181b2a1b6589c1372994f837730e0205f9`；同一 Release 附构建信息与校验文件。1.2.6 私有候选 APK 的 asset SHA-256 为 `4e80c223ac7043e0b937546e6ed0b0e548ba0de2b9d3d7f78e179cee8eecaa80`。这里核对的是发行元数据，未重新下载或安装 APK。

当前主线另包含 **iOS 3.2.6 / build 1 的源码准备**（App、Widget、Share Extension 一致）。尚未据此执行 Apple 正式发布或创建正式 tag；不能覆盖上表的已核实商店记录。

## 其他正式 Android 源码锚点

以下来自 GitHub 正式 Release 与 tag，更新说明和产物链接直接使用 Release，不再复制长篇摘要。历史真机结果只在有原始证据时补录。

| 版本 | code | 正式源码 | Release |
|---|---|---|---|
| 1.2.2 | 6 | `39af5c96df85fcb1284cfc33a2e38ac77b211d26` | [android-v1.2.2](https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.2.2) |
| 1.2.1 | 5 | `766f8a7a661143cfba2c26e6adf8986776c61e88` | [android-v1.2.1](https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.2.1) |
| 1.2.0 | 4 | `8c8e4b8418250a89ed89fa9bf59f579081c00a34` | [android-v1.2.0](https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.2.0) |
| 1.1.0 | 3 | `5cbc577a56f84aace46d4dd5d977632056115d83` | [android-v1.1.0](https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.1.0) |

新增发行沿用上面的最小字段：平台/version、状态、versionCode/build、精确源码、不可变 tag、正式产物或商店证据、验收结果/缺口和核对日期。源码版本变化不自动新增正式发行，未核实字段明确保留；不要移动旧 tag 补齐缺失信息。

## Android 1.0.1

| 项目 | 内容 |
|---|---|
| 状态 | 已正式发布（2026-08-31） |
| 最低系统 | Android 10（API 29） |
| Git tag | `android-v1.0.1` |
| 发布源码 | `ad7915c7f71278c9c10e8320c2f959c8cbd9aa91` |
| GitHub Release | [`MyLeafy Android 1.0.1`](https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.0.1) |
| 产物 | 签名 APK、SHA-256、构建信息 |
| APK SHA-256 | `de264f79890849f85b6aa716233e6ab03920b4db39cc055971aa41ae1a134ea5` |
| 真机验收 | Xiaomi 24069RA21C / Android 16：保留身份与本地数据覆盖安装、冷启动及社区加载通过 |

此热修复保留登录失败原因，并为社区 TLS 连接被当前网络拦截的情况提供安全、可操作的提示；不会关闭证书主机名校验。

## Android 1.0.0

| 项目 | 内容 |
|---|---|
| 状态 | 已正式发布（2026-08-31） |
| 最低系统 | Android 10（API 29） |
| Git tag | `android-v1.0.0` |
| 发布源码 | `24da9e18d36a3a8b759c368700f79553a39a2f08` |
| GitHub Release | [`MyLeafy Android 1.0.0`](https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.0.0) |
| 产物 | 签名 APK、SHA-256、构建信息 |
| APK SHA-256 | `099c77d5a5e63fbc2f5e9aac21353062f85c6038112e9dee7dda8bca978435b5` |
| 真机验收 | Xiaomi 24069RA21C / Android 16：安装、冷启动与根页面渲染通过 |

用户可见更新说明见 [`android-release-notes.md`](android-release-notes.md)。Android Release 不包含 iOS 二进制。

## 2.9

| 项目 | 内容 |
|---|---|
| 状态 | 已正式发布 |
| App Store 发布时间 | 2026-08-03 |
| Build | 27 |
| Git tag | `v2.9` |
| 发布源码 | `6d5c0331266b49461153fb47b9a17a1f37e5a230` |

App Store 实际更新说明：

```text
为新学期做准备。
```

根据 Git 历史补录的版本摘要：

- 统一考试、自定日程、倒计时与提醒的时间表达，并完善课表背景和共享课表体验。
- 扩展社区附件、评论、草稿、发布任务与本地分享卡片，提升内容发布和恢复能力。
- 完善账户永久删除、审核演示账号和关键异常反馈，修复审核阶段发现的稳定性问题。

## 2.8

| 项目 | 内容 |
|---|---|
| 状态 | 历史正式版本 |
| 源码定版日期 | 2026-07-13 |
| Build | 19 |
| Git tag | `v2.8` |
| 发布源码 | `716cb3e50f4cf73a3d95ef82959f3091106d60a1` |

根据 Git 历史补录的版本摘要：

- 根导航迁移到原生系统 Tab，并优化课表快捷入口、天气提示和校园页面细节。

- 加强邮箱验证、认证链路、运营后台和数据库操作的安全性与可靠性。

## 1.9

App Store 更新说明：

```text
MyLeafy 1.9 优化校园功能流程和多语言体验。

学习项目现在支持删除，并可选择保留资料、任务和学习记录到“其他”，或连同项目内容一起清理。学业与职业模块的行操作也更紧凑，减少误触和视觉占用。

本次还调整了共享课表、荣誉记录和小组件的本地化表达，补充繁体中文文案，并将英文品牌字体改为 Lora。
```

## 1.6

App Store 更新说明：

```text
MyLeafy 1.6 调整了社区信息层级，并优化了校园功能的操作流程。

置顶内容现在会在社区中更醒目地显示。我们也优化了帖子流、反馈、评教和共享课表的细节体验，并提升了整体稳定性。
```
