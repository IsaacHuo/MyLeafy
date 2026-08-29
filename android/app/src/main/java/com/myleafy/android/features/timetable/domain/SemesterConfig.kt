package com.myleafy.android.features.timetable.domain

import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * 学期运行配置（对应 iOS `SemesterRuntimeConfig` / `semester_runtime_configs` 表）。
 * 阶段 1.5 使用内置配置；阶段 2 从 Supabase 拉取远程 active 配置覆盖。
 */
data class SemesterRuntimeConfig(
    val semesterId: String,
    val semesterStartDate: LocalDate,
    val supportedWeeks: Int,
    val graduateTimetableTermCode: String,
    val calendarEvents: List<SchoolCalendarEvent>,
    val updatedAt: String?,
    val isActive: Boolean,
) {
    val isUsable: Boolean
        get() = semesterId.isNotBlank() &&
            graduateTimetableTermCode.isNotBlank() &&
            supportedWeeks > 0

    companion object {
        val previousSpring = SemesterRuntimeConfig(
            semesterId = "2025-2026-2",
            semesterStartDate = LocalDate.of(2026, 3, 9),
            supportedWeeks = 20,
            graduateTimetableTermCode = "46",
            calendarEvents = listOf(
                SchoolCalendarEvent(
                    id = "bjfu-sports-2026",
                    title = "运动会停课",
                    startDate = LocalDate.of(2026, 4, 24),
                    endDate = LocalDate.of(2026, 4, 24),
                    kind = SchoolCalendarEvent.Kind.CLOSURE,
                ),
                SchoolCalendarEvent(
                    id = "bjfu-semester-end-2026-spring",
                    title = "学期结束",
                    startDate = LocalDate.of(2026, 7, 26),
                    endDate = LocalDate.of(2026, 7, 26),
                    kind = SchoolCalendarEvent.Kind.HOLIDAY,
                    academicCategory = SchoolCalendarEvent.AcademicCategory.SEMESTER_END,
                ),
                SchoolCalendarEvent(
                    id = "bjfu-summer-break-2026",
                    title = "暑假",
                    startDate = LocalDate.of(2026, 7, 27),
                    endDate = LocalDate.of(2026, 9, 6),
                    kind = SchoolCalendarEvent.Kind.HOLIDAY,
                    academicCategory = SchoolCalendarEvent.AcademicCategory.SUMMER_BREAK,
                ),
            ),
            updatedAt = null,
            isActive = false,
        )

        val builtIn = SemesterRuntimeConfig(
            semesterId = "2026-2027-1",
            semesterStartDate = LocalDate.of(2026, 9, 7),
            supportedWeeks = 20,
            graduateTimetableTermCode = "47",
            calendarEvents = listOf(
                SchoolCalendarEvent(
                    id = "bjfu-midautumn-2026",
                    title = "中秋节",
                    startDate = LocalDate.of(2026, 9, 25),
                    endDate = LocalDate.of(2026, 9, 27),
                    kind = SchoolCalendarEvent.Kind.HOLIDAY,
                    academicCategory = SchoolCalendarEvent.AcademicCategory.PUBLIC_HOLIDAY,
                ),
                SchoolCalendarEvent(
                    id = "bjfu-national-day-2026",
                    title = "国庆节",
                    startDate = LocalDate.of(2026, 10, 1),
                    endDate = LocalDate.of(2026, 10, 7),
                    kind = SchoolCalendarEvent.Kind.HOLIDAY,
                    academicCategory = SchoolCalendarEvent.AcademicCategory.PUBLIC_HOLIDAY,
                ),
                SchoolCalendarEvent(
                    id = "bjfu-anniversary-74-2026",
                    title = "建校74周年校庆日",
                    startDate = LocalDate.of(2026, 10, 16),
                    endDate = LocalDate.of(2026, 10, 16),
                    kind = SchoolCalendarEvent.Kind.HOLIDAY,
                    academicCategory = SchoolCalendarEvent.AcademicCategory.IMPORTANT_DATE,
                ),
                SchoolCalendarEvent(
                    id = "bjfu-new-year-2027",
                    title = "元旦",
                    startDate = LocalDate.of(2027, 1, 1),
                    endDate = LocalDate.of(2027, 1, 3),
                    kind = SchoolCalendarEvent.Kind.HOLIDAY,
                    academicCategory = SchoolCalendarEvent.AcademicCategory.PUBLIC_HOLIDAY,
                ),
                SchoolCalendarEvent(
                    id = "bjfu-first-semester-end-2027",
                    title = "第一学期结束",
                    startDate = LocalDate.of(2027, 1, 15),
                    endDate = LocalDate.of(2027, 1, 15),
                    kind = SchoolCalendarEvent.Kind.HOLIDAY,
                    academicCategory = SchoolCalendarEvent.AcademicCategory.SEMESTER_END,
                ),
                SchoolCalendarEvent(
                    id = "bjfu-winter-break-2027",
                    title = "寒假",
                    startDate = LocalDate.of(2027, 1, 16),
                    endDate = LocalDate.of(2027, 2, 27),
                    kind = SchoolCalendarEvent.Kind.HOLIDAY,
                    academicCategory = SchoolCalendarEvent.AcademicCategory.WINTER_BREAK,
                ),
            ),
            updatedAt = null,
            isActive = true,
        )

        val builtInTimeline: List<SemesterRuntimeConfig> = listOf(previousSpring, builtIn)
    }
}

/**
 * 校历事件（对应 iOS `SchoolCalendarEvent`）。
 */
data class SchoolCalendarEvent(
    val id: String,
    val title: String,
    val startDate: LocalDate,
    val endDate: LocalDate,
    val kind: Kind,
    val academicCategory: AcademicCategory? = null,
) {
    enum class Kind { HOLIDAY, CLOSURE, SOLAR_TERM }

    enum class AcademicCategory {
        PUBLIC_HOLIDAY, IMPORTANT_DATE, SEMESTER_END, WINTER_BREAK, SUMMER_BREAK,
    }

    val isPublicHoliday: Boolean
        get() = kind == Kind.HOLIDAY &&
            (academicCategory == null || academicCategory == AcademicCategory.PUBLIC_HOLIDAY)

    val isVacation: Boolean
        get() = academicCategory == AcademicCategory.WINTER_BREAK ||
            academicCategory == AcademicCategory.SUMMER_BREAK

    fun contains(date: LocalDate): Boolean = !date.isBefore(startDate) && !date.isAfter(endDate)
}

/**
 * 学期配置门面（对应 iOS `SemesterConfig`）。
 * 阶段 1.5 固定内置配置；阶段 2 支持远程 active 配置与缓存回退。
 */
object SemesterConfig {
    const val timetableWeekCapacity = 20

    var current: SemesterRuntimeConfig = SemesterRuntimeConfig.builtIn
        internal set

    val timelineConfigurations: List<SemesterRuntimeConfig>
        get() = (SemesterRuntimeConfig.builtInTimeline + listOf(current))
            .distinctBy { it.semesterId }
            .sortedBy { it.semesterStartDate }

    val currentSemesterId: String get() = current.semesterId
    val startOfSemesterDate: LocalDate get() = current.semesterStartDate
    val supportedWeeks: Int get() = timetableWeekCapacity
    val graduateTimetableTermCode: String get() = current.graduateTimetableTermCode
    val calendarEvents: List<SchoolCalendarEvent> get() = current.calendarEvents

    /** 当前教学周：按学期首日计算，夹在 1..capacity。 */
    fun currentWeek(date: LocalDate = LocalDate.now()): Int {
        val days = ChronoUnit.DAYS.between(startOfSemesterDate, date)
        return if (days < 0) 1 else ((days + 7) / 7).toInt().coerceIn(1, timetableWeekCapacity)
    }

    /** (教学周, 周几)：day 周一=1 … 周日=7。 */
    fun weekAndDay(date: LocalDate = LocalDate.now()): WeekAndDay {
        val days = ChronoUnit.DAYS.between(startOfSemesterDate, date)
        val week = if (days < 0) 1 else (days / 7 + 1).toInt().coerceIn(1, timetableWeekCapacity)
        return WeekAndDay(week = week, day = date.dayOfWeek.value)
    }

    data class WeekAndDay(val week: Int, val day: Int)
}
