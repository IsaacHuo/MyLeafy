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
```

要求：JDK 17+，Android SDK（`local.properties` 中 `sdk.dir`）。

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

教务抓取、jsoup 解析、Supabase 接入在后续阶段按
`docs/engineering/android-migration.md` 推进。
