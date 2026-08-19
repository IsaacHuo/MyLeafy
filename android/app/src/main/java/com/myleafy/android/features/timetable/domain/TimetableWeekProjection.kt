package com.myleafy.android.features.timetable.domain

import com.myleafy.android.core.data.local.CourseEntity

/** 某周某天的课程单元格（起点节次 + 跨度节数）。 */
data class WeekCourseCell(
    val course: CourseEntity,
    val startPeriod: Int,
    val rowSpan: Int,
)

/**
 * 周课表投影（对应 iOS `WeeklyTimetableProjection`）。
 * 纯计算：按 (周次, 周几) 过滤课程并计算节次跨度，供网格渲染一次性使用。
 */
object TimetableWeekProjection {

    val dayLabels = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")

    /** 某周课程按天分组：day(1..7) → 按开始节次排序的课程列表。 */
    fun projectWeek(courses: List<CourseEntity>, week: Int): Map<Int, List<WeekCourseCell>> =
        courses
            .filter { it.weeks.contains(week) }
            .groupBy { it.dayOfWeek }
            .mapValues { (_, dayCourses) ->
                dayCourses
                    .map { course ->
                        val duration = course.duration.sorted()
                        WeekCourseCell(
                            course = course,
                            startPeriod = duration.firstOrNull() ?: 1,
                            rowSpan = duration.size.coerceAtLeast(1),
                        )
                    }
                    .sortedBy { it.startPeriod }
            }

    /** 某周某天的课程（空列表表示无课）。 */
    fun coursesForDay(courses: List<CourseEntity>, week: Int, day: Int): List<WeekCourseCell> =
        projectWeek(courses, week)[day] ?: emptyList()
}
