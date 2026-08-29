# MyLeafy Android

MyLeafy 的 Android 原生客户端（单 `app` module）。迁移方案与教务协议记录见
[`docs/engineering/android-migration.md`](../docs/engineering/android-migration.md)。

## 技术栈

- Kotlin + Jetpack Compose + Material 3
- Room（本地数据）、DataStore（设置）、Navigation Compose（导航 + 深链）
- minSdk 29 / targetSdk 36 / compileSdk 36
- 版本目录 `gradle/libs.versions.toml`

## 构建

```bash
./gradlew assembleDebug            # 产出 app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest        # 纯 JVM 单元测试
./gradlew connectedDebugAndroidTest # 运行 5 Tab / 二级导航设备烟雾测试
```

要求：JDK 17+，Android SDK Platform 36（`local.properties` 中 `sdk.dir`）。Windows 本地可直接使用 Android Studio 自带 JBR；本仓库的 wrapper 下载超时已放宽，适合首次获取 Gradle 分发包。

模拟器验收基线：Pixel 8、Android 16 / API 36、Google APIs x86_64。App 默认直接进入主界面，学校登录从“我的”进入。

若宿主机浏览器可访问教务、模拟器却收到 `502`，先检查 VPN/代理是否以全局模式接管模拟器 NAT 流量。应让 `newjwxt.bjfu.edu.cn` 和 `202.204.121.79` 直连，或在验收时关闭对应代理；不要把个人代理地址或凭据写进 App。可用 `adb shell settings get global http_proxy` 检查模拟器是否遗留系统代理。

## 配置

Supabase 公开配置位于 git-ignored `secrets.properties`（从
`secrets.properties.example` 复制并填写 publishable/anon key）：

```bash
cp secrets.properties.example secrets.properties
```

> 只允许公开的 project URL 与 anon key；严禁 service_role 或任何私密凭据。

## 目录

```
app/src/main/java/com/myleafy/android/
├── navigation/    # RootTab + MyLeafyNavHost + Routes（5 Tab + login + 深链）
├── features/      # auth / timetable / community / schedule / campus / profile
├── core/          # campus / data(local Room v2) / di / network / prefs(DataStore) / security
├── parsers/       # HtmlParser 接口（jsoup 阶段 2）
├── services/      # SupabaseConfig
├── shared/model/  # 社区 DTO（snake_case，跨平台契约）
└── ui/            # theme / 根组合 / 公共组件
```

## 状态

第一阶段（2026-08）与 1.5（2026-08）：可编译、可运行、5 Tab 可导航的完整基础架构。
- 课表：学期/周次纯逻辑 + Room 缓存展示；
- 日迹：随记/日程本地 CRUD（真实可用）；
- 社区/校园/我的：Repository + UiState + 占位实现（如实提示未接入）；
- 登录路由与 `myleafy://` 深链已接入。

当前 UI 壳采用 Material 3：5 个根页面保留底部导航，二级页面隐藏底栏并使用系统返回栏；常用未实现入口由 `FeatureDestination` 进入明确占位页。帮助中心、权限说明、关于与内置校历为可直接使用的静态页面。页面只展示真实 Room/教务/Supabase 数据，不注入演示数据；未登录、未配置或校园网不可达时展示真实空状态或错误。

教务抓取、jsoup 解析与 Supabase 基础链路已经接入；后续功能范围按
`docs/engineering/android-migration.md` 推进。

2026-08-29 已在 `MyLeafy_API_36` 上真实验证本科验证码与登录。当前学校课表响应不含 Android 解析器支持的 `kbcontent/kbtable` 结构，因此课表同步会明确报“课表数据不可用”并保留本地缓存；WebView/bootstrap 回退留待后续教务专项完成。
