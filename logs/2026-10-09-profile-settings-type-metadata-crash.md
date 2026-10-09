# Profile 设置列表的类型元数据崩溃

## 现场证据

Xcode 连接真机的暂停现场显示主线程 `EXC_BAD_ACCESS`，不在教室请求或缓存读写路径。提取的关键栈为：

```text
swift::SubstGenericParametersFromMetadata::getMetadata
swift::Demangle::TypeDecoder::decodeMangledType / decodeGenericArgs
swift_getTypeByMangledNameInContext2
__swift_instantiateConcreteTypeFromMangledNameV2
ProfileView.settingsRows.getter (修复前 ProfileView.swift:239)
ProfileView.profileSettingsList.getter
ProfileView.body.getter
```

启动日志表明学校/社区启动链已运行，崩溃触发在 Profile 根列表准备设置行的类型元数据阶段。构建和业务单测通过不能证明此处安全：离线 XCTest 宿主不挂载生产根页面。当前 iOS 27 Simulator 可显示登录页、演示课表、校园的三个内容区和分享页，未复现同一真机崩溃，不能据此宣称真机问题不存在。

## 针对触发结构的修复

原设置行把同步、共享课表、个性化和背景页的直接 NavigationLink 目标类型一起嵌进复合 ViewBuilder 返回类型。改为已有 ProfileRoute 的值导航，并将设置行、行标签和周末开关拆为具名 View，使根列表使用浅层、稳定的类型边界。共享课表外部邀请码仍沿用原请求，返回根路径后清除暂存值，避免手动打开时复用旧邀请码。

Startup 日志记录 App 初始化和模型容器准备阶段；ProfileNavigation 日志记录设置路由准备和根页出现，不记录账号凭据或随记内容。修复后的真机结果必须由用户重新运行验证；Simulator 的未复现结果不能作为真机修复确认。

## 与 await 警告的区别

LiveClassroomLookupService 的六条 warning 来自同一 MainActor 上同步初始化/校验的多余 await。删除这些 await 不删除身份与取消检查，也不把网络或异步缓存改为同步。它们与上述 Profile 类型元数据崩溃是不同问题。

## 本地验证边界

修复后的 iOS 17 最低目标 Simulator 构建通过（0 警告、0 错误）。在独立 iOS 27 Simulator 重新安装、以演示模式启动，能够进入我的与个性化页，运行日志出现 ProfileNavigation 的路由准备和根页出现标记。Simulator 的社区恢复因缺少签名授权报安全存储失败，已按现有错误路径显示，未通过降低 Keychain 安全策略绕过。没有向用户真机安装修复版，也没有继续或重置其暂停现场；真机是否恢复需要用户重新构建运行确认。
