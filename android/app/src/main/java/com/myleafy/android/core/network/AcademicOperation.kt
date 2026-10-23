package com.myleafy.android.core.network

enum class AcademicStage(val label: String) {
    FETCHING_TIMETABLE("正在获取课表"),
    INITIALIZING_TIMETABLE("正在打开课表页面"),
    PROCESSING_TIMETABLE("正在处理课表"),
    SAVING_TIMETABLE("正在保存课表"),
}

enum class AcademicStepStatus { RUNNING, COMPLETED, FAILED }

/**
 * 用户主动教务操作的一步。运行中显示进度，完成后保留打勾，
 * 失败时保留原因；不再用一行“正在同步”覆盖整个历史。
 */
data class AcademicStep(
    val key: String,
    val label: String,
    val status: AcademicStepStatus = AcademicStepStatus.RUNNING,
    val detail: String? = null,
)

data class TimetableRefreshResult(
    val courseCount: Int,
    val arrangementCount: Int,
    val changed: Boolean,
    /** 学校本次返回了可信空课表，但为了不误删本地数据而没有落库。 */
    val retainedExisting: Boolean = false,
) {
    val message: String
        get() = when {
            retainedExisting -> "学校本次未返回课程，已保留本地课表；备注、提醒和个人日程保持不变。"
            arrangementCount == 0 -> "同步完成，学校当前没有返回课程安排。"
            !changed -> "同步完成，课表已是最新，共 $courseCount 门课程、$arrangementCount 条安排。"
            else -> "同步完成，共 $courseCount 门课程、$arrangementCount 条安排。"
        }
}
