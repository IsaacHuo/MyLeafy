package com.myleafy.android.core.network

/**
 * 教务网络错误语义（对应 iOS `SchoolNetworkError`，行为契约一致）。
 */
sealed class SchoolNetworkError(val message: String) {
    class LoginFailed(reason: String) : SchoolNetworkError(reason)
    object SessionExpired : SchoolNetworkError("教务会话已失效")
    object TimetableDataUnavailable : SchoolNetworkError("课表数据不可用")
    object TimetableQueryFormNotFound : SchoolNetworkError("未找到课表查询表单")
    object TimetableSemesterMismatch : SchoolNetworkError("课表学期不匹配")
    object ClassroomDataUnavailable : SchoolNetworkError("空教室数据不可用")
    object FeatureUnavailable : SchoolNetworkError("功能不可用")
    object CampusNetworkRequired : SchoolNetworkError("只能校园网内访问")
    class Unexpected(reason: String) : SchoolNetworkError(reason)
}
