# 代码风格与格式工具

Swift 和 Kotlin 各用成熟格式工具，规则限定为排版。工具配置、纯格式化与功能修改分开提交；不改变 API、声明、字符串实际值、数据库或截图基准，不在构建阶段改写源码。

## 固定版本与范围

| 工具 | 固定版本 | 版本来源 |
|---|---|---|
| SwiftFormat | 0.64.1 | `scripts/format-swift.sh`，官方下载 ZIP 的 SHA-256 同时固定 |
| Spotless | 8.10.4 | Android version catalog |
| ktlint | 1.8.0 | Android version catalog，Spotless 显式使用 |

Swift 脚本在 macOS 首次下载校验后的官方二进制，缓存于 `${XDG_CACHE_HOME:-$HOME/Library/Caches}/MyLeafy/SwiftFormat/0.64.1`，不安装 Homebrew 全局工具；本地与 iOS CI 使用同一脚本。缓存版本不符会明确失败。升级工具要单独验证规则、幂等性和完整相关 CI，不使用浮动 latest。

默认 Swift 范围为 leafy、leafyTests、leafyWidget、LeafyWidgetShared、LeafyShareExtension、LeafyExternalImportShared。Android 在根 Gradle 工程统一覆盖 `app/src/**/*.kt`（main/test/androidTest）及根、app 的三个 `.gradle.kts`。依赖、生成代码、构建目录、fixtures、Room schema、截图图片不在格式化范围内。

根 `.editorconfig` 按 Swift/Kotlin 限定四空格、LF、末尾换行和 120 列参考宽度。SwiftFormat 显式白名单控制空白与换行；ktlint 用 android_studio 风格及排版白名单，暂不开命名、声明、导入或字符串内容改写。120 列是参考，不能为达到硬限制拆字符串、改声明或改变语义。Markdown 保留行尾双空格。

## 本地命令

在仓库根目录执行 Swift 格式化与只读检查，带路径时仅处理自己的任务文件；省略路径检查全部自有 Swift：

```bash
bash scripts/format-swift.sh leafy/App/ContentView.swift
bash scripts/format-swift.sh --check leafy/App/ContentView.swift
bash scripts/format-swift.sh --check
```

Android 从 android 目录运行：

```bash
./gradlew spotlessApply
./gradlew spotlessCheck
```

存在无关编辑时，Spotless 的 IDE hook 可限定一个或多个**绝对路径**；不要传相对路径，因为 Spotless 不会处理这些输入：

```bash
./gradlew spotlessApply -PspotlessIdeHook="$PWD/app/src/main/java/com/myleafy/android/features/profile/ProfileSyncScreen.kt"
./gradlew spotlessCheck
```

多个路径用逗号分隔，不含额外空格。只检查发现其他人的未提交格式问题时保留并说明，不自动修改或纳入本任务提交。没有无关编辑的专用 worktree 可执行完整 apply/check。

## CI 与验证

Swift 检查在 iOS 构建前执行，Spotless 检查在 Android 构建前执行，都由既有 `CI result` 汇总。`.swiftformat` 和 Swift 脚本变化选择 iOS，`.editorconfig` 选择双端，Android 下的配置选择 Android；工作流和 CI 范围脚本变化验证全部检查。范围回归在 `scripts/test_ci_changes.py`。

CI 失败会打印相同修复入口，不自动提交格式。格式问题不得通过忽略整个旧代码库、持续放宽规则或重录截图隐藏。

全量格式化分别提交两个平台；用非空白 diff、Swift 编译器解析的字符串值、相关构建和完整 CI 检查行为。再次执行 formatter 后必须无 diff。纯格式化提交保存在根 `.git-blame-ignore-revs`；可在当前 checkout 配置：

```bash
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

该配置仅影响 blame 展示，不改变 Git 历史。重排任务提交后要同步修正文件中的 SHA。

后续 SwiftLint、Detekt 或结构重构需独立 Issue 和具体验收理由，本轮不引入。
