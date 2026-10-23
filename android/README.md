# MyLeafy Android

Android 原生客户端，与 iOS、Cloudflare 后端和官网共用仓库，独立发版。[跨端状态](../state/PLATFORMS.md) 区分实现、验证和正式交付；[当前架构](../state/ARCHITECTURE.md) 是代码结构入口，[对齐方案](../docs/engineering/android-migration.md) 记录取舍。

## 技术与结构

Kotlin、Compose / Material 3、Room、DataStore、Navigation Compose、WorkManager / AlarmManager、OkHttp 与 jsoup。最低 API 29，target/compile SDK 36；依赖版本在 `gradle/libs.versions.toml`。新版业务调用 Cloudflare `/v1`，不接入旧 Supabase SDK。

`app/src/main/java/com/myleafy/android/` 下：

- `navigation/`：RootTab、MyLeafyNavHost 与深链；课表、校园、我的三个根入口，社区与日迹从校园「校园生活」进入。
- `features/`：auth、timetable、community、schedule、campus、profile。
- `core/`：校园作用域、Room、依赖、网络、偏好和凭据。
- `parsers/`、`services/`、`shared/model/`：学校 HTML 解析、学校/Cloudflare 服务与 DTO。
- `ui/`：主题、公共组件与根组合。

无身份先显示北京林业大学与免登录入口，恢复身份后进入根导航。小屏底部导航、宽屏 Navigation Rail；二级页面隐藏根导航。云同步、Widget 等能力不根据旧 README 推断，逐项以状态矩阵及源码核对。

## 构建与检查

安装 JDK 17+ 和 Android SDK Platform 36，将本机 SDK 路径放在未跟踪的 `local.properties` 或 `ANDROID_HOME`。Gradle daemon 使用受版本控制的 `gradle/gradle-daemon-jvm.properties` 指定的 toolchain（当前 Oracle 24），由已有 resolver 查找/准备；不要为了格式工具改动应用 toolchain。

从 android 目录执行：

```bash
./gradlew spotlessApply             # 修改自有 Kotlin 与 Gradle 脚本
./gradlew spotlessCheck             # 只读检查
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
./gradlew :app:lintDebug
./gradlew :app:verifyRoborazziDebug -Pscreenshot
```

格式工具版本与只处理任务文件的方式见 [代码规范](../docs/engineering/code-style.md)。`connectedDebugAndroidTest` 需要独立设备；Debug 包名带 `.next`，可并存，但不能代替正式包覆盖升级验收。不要因格式变化重录截图。

## 服务配置与发布

默认 API 为 `https://api.myleafy.space`；隔离环境传 `-PmyleafyApiOrigin=https://api-staging.myleafy.space`。本地 SDK、签名材料、凭据与学生数据禁止提交。

Release 构建必须配置 `MYLEAFY_RELEASE_STORE_FILE`、`MYLEAFY_RELEASE_STORE_PASSWORD`、`MYLEAFY_RELEASE_KEY_ALIAS`、`MYLEAFY_RELEASE_KEY_PASSWORD`，缺失即失败。main CI 通过后为新 versionCode 准备私有签名候选；超级管理员下载验收后授权发布同一 APK，不重新构建。来源、版本、SHA-256 和验收按 [交付手册](../docs/operations/delivery.md) 与 [发布索引](../docs/operations/release-notes.md) 核对。

学校教务依赖校园网或学校认可的 VPN。出现学校网页能访问、设备请求却 502 时检查设备代理及网络路径，不把个人代理地址或凭据写入应用，也不关闭 TLS 校验。
