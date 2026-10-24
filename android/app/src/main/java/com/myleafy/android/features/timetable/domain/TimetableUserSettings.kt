package com.myleafy.android.features.timetable.domain

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

/**
 * 用户可编辑的课表时间配置（对应 iOS `UserTimetableSettings`）。
 *
 * 学期名称和开学日期只影响显示与周次投影，不改变已拉取课程的存储学期；
 * 节次数量与作息同时驱动课表网格、课程详情和提醒锚点。
 */
data class TimetableUserSettings(
    val academicYear: Int = 2026,
    val term: Int = 1,
    val firstMonday: LocalDate = LocalDate.of(2026, 9, 7),
    val periods: List<TimetablePeriodSchedule.Slot> = TimetablePeriodSchedule.defaultSlots,
) {
    val summary: String
        get() = "$academicYear–${academicYear + 1} 学年 · 第 $term 学期"

    val periodCount: Int get() = periods.size

    val validationError: String?
        get() {
            if (academicYear !in 1900..2200) return "学年需在 1900–2200 之间"
            if (term !in 1..2) return "学期只能选择第一或第二学期"
            if (firstMonday.dayOfWeek != DayOfWeek.MONDAY) return "开学日期必须是星期一"
            if (periods.size !in 1..24) return "每天节次需在 1–24 之间"
            periods.forEachIndexed { index, slot ->
                if (slot.period != index + 1) return "节次编号不连续"
                if (slot.startHour !in 0..23 || slot.endHour !in 0..23 ||
                    slot.startMinute !in 0..59 || slot.endMinute !in 0..59
                ) {
                    return "第 ${index + 1} 节时间格式无效"
                }
                if (slot.startMinutes >= slot.endMinutes) return "第 ${index + 1} 节开始时间必须早于结束时间"
                if (index > 0 && periods[index - 1].endMinutes > slot.startMinutes) {
                    return "第 ${index + 1} 节与上一节时间重叠"
                }
            }
            return null
        }

    val isValid: Boolean get() = validationError == null

    fun withPeriodCount(count: Int): TimetableUserSettings {
        val target = count.coerceIn(1, 24)
        val resized = when {
            target == periods.size -> periods
            target < periods.size -> periods.take(target)
            else -> buildList {
                addAll(periods)
                while (size < target) {
                    val index = size
                    val default = TimetablePeriodSchedule.defaultSlots.getOrNull(index)
                    if (default != null) {
                        add(default.copy(period = index + 1))
                    } else {
                        val previous = last()
                        val remaining = target - size
                        val start = previous.endMinutes + 1
                        val available = (23 * 60 + 59 - start).coerceAtLeast(remaining)
                        // 新增一节时优先沿用 45 分钟；一次补到 24 节时按剩余时间均分，
                        // 保证自动生成的作息仍然合法，用户可再逐节微调。
                        val duration = if (remaining == 1) {
                            available.coerceAtMost(45)
                        } else {
                            ((available - (remaining - 1)) / remaining).coerceAtLeast(1)
                        }
                        val end = (start + duration).coerceAtMost(23 * 60 + 59)
                        add(
                            TimetablePeriodSchedule.Slot(
                                period = index + 1,
                                startHour = start / 60,
                                startMinute = start % 60,
                                endHour = end / 60,
                                endMinute = end % 60,
                            ),
                        )
                    }
                }
            }
        }
        return copy(periods = resized.mapIndexed { index, slot -> slot.copy(period = index + 1) })
    }

    companion object {
        fun mondayOf(date: LocalDate): LocalDate =
            date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    }
}
