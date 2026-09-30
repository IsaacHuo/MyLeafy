package com.myleafy.android.core.network

enum class AcademicStage(val label: String) {
    FETCHING_TIMETABLE("正在获取课表"),
    INITIALIZING_TIMETABLE("正在打开课表页面"),
    PROCESSING_TIMETABLE("正在处理课表"),
    SAVING_TIMETABLE("正在保存课表"),
}

data class TimetableRefreshResult(val courseCount: Int, val arrangementCount: Int, val changed: Boolean) {
    val message: String get() = when {
        arrangementCount == 0 -> "同步完成，学校当前没有返回课程安排。"
        !changed -> "同步完成，课表已是最新，共 $courseCount 门课程、$arrangementCount 条安排。"
        else -> "同步完成，共 $courseCount 门课程、$arrangementCount 条安排。"
    }
}
