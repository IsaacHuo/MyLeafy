package com.myleafy.android.features.timetable.domain

/**
 * 节次时间表（对应 iOS `TimetablePeriodSchedule`，13 节固定时段）。
 */
object TimetablePeriodSchedule {

    data class Slot(
        val period: Int,
        val startHour: Int,
        val startMinute: Int,
        val endHour: Int,
        val endMinute: Int,
    ) {
        val startText: String get() = "%02d:%02d".format(startHour, startMinute)
        val endText: String get() = "%02d:%02d".format(endHour, endMinute)
        val startMinutes: Int get() = startHour * 60 + startMinute
        val endMinutes: Int get() = endHour * 60 + endMinute
    }

    val slots: List<Slot> = listOf(
        Slot(1, 8, 0, 8, 45),
        Slot(2, 8, 50, 9, 35),
        Slot(3, 9, 50, 10, 35),
        Slot(4, 10, 40, 11, 25),
        Slot(5, 11, 30, 12, 15),
        Slot(6, 13, 30, 14, 15),
        Slot(7, 14, 20, 15, 5),
        Slot(8, 15, 20, 16, 5),
        Slot(9, 16, 10, 16, 55),
        Slot(10, 18, 30, 19, 15),
        Slot(11, 19, 20, 20, 5),
        Slot(12, 20, 10, 20, 55),
        Slot(13, 21, 0, 21, 45),
    )

    fun slot(period: Int): Slot? = slots.firstOrNull { it.period == period }

    /** 当前时间所属节次（不到开始时间则返回之后的第一个节次）。 */
    fun periodForFocus(minutesOfDay: Int): Slot? =
        slots.firstOrNull { minutesOfDay <= it.endMinutes } ?: slots.last()

    /** 当前时间落在其中的节次。 */
    fun period(minutesOfDay: Int): Slot? =
        slots.firstOrNull { minutesOfDay in it.startMinutes..it.endMinutes }

    fun defaultStudyPeriod(minutesOfDay: Int): Int = periodForFocus(minutesOfDay)?.period ?: 1

    /** 与时间区间重叠的节次范围。 */
    fun periodRange(startMinutes: Int, endMinutes: Int): IntRange? {
        if (endMinutes <= startMinutes) return null
        val periods = slots
            .filter { startMinutes < it.endMinutes && endMinutes > it.startMinutes }
            .map { it.period }
        if (periods.isEmpty()) return null
        return periods.first()..periods.last()
    }
}
