package com.myleafy.android.features.timetable.domain

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

data class TimetableWeekRange(
    val week: Int,
    val startDate: LocalDate,
) {
    val endDateExclusive: LocalDate get() = startDate.plusDays(7)
}

data class TimetableGridCourse(
    val id: String,
    val name: String,
    val teacher: String,
    val location: String,
    val room: String,
    val dayOfWeek: Int,
    val weeks: List<Int>,
    val periods: List<Int>,
)

data class TimetableGridExam(
    val id: String,
    val name: String,
    val location: String,
    val date: LocalDate,
    val startTime: LocalTime,
    val endTime: LocalTime,
)

data class TimetableGridScheduleEvent(
    val id: String,
    val title: String,
    val location: String?,
    val startsAt: Long,
    val endsAt: Long?,
)

enum class TimetableGridItemType { COURSE, EXAM, SCHEDULE }

data class TimetableGridItem(
    val stableId: String,
    val sourceId: String,
    val type: TimetableGridItemType,
    val title: String,
    val subtitle: String?,
    val dayIndex: Int,
    val startPeriod: Int,
    val periodSpan: Int,
    val lane: Int,
    val laneCount: Int,
) {
    val endPeriod: Int get() = startPeriod + periodSpan - 1
}

data class TimetableGridSnapshot(
    val weekRange: TimetableWeekRange,
    val items: List<TimetableGridItem>,
)

/** Pure, precomputed geometry input for the Compose timetable grid. */
object TimetableGridProjection {
    val campusZone: ZoneId = ZoneId.of("Asia/Shanghai")

    fun project(
        courses: List<TimetableGridCourse>,
        exams: List<TimetableGridExam>,
        scheduleEvents: List<TimetableGridScheduleEvent>,
        weekRange: TimetableWeekRange,
    ): TimetableGridSnapshot {
        val rawItems = buildList {
            courses
                .asSequence()
                .filter { weekRange.week in it.weeks && it.dayOfWeek in 1..7 }
                .mapNotNull { course ->
                    val periods = course.periods.filter { it in 1..13 }.distinct().sorted()
                    if (periods.isEmpty()) return@mapNotNull null
                    RawItem(
                        stableId = "course:${course.id}:${weekRange.week}",
                        sourceId = course.id,
                        type = TimetableGridItemType.COURSE,
                        title = course.name,
                        subtitle = listOf(course.location, course.room).filter(String::isNotBlank).joinToString(" ")
                            .ifBlank { null },
                        dayIndex = course.dayOfWeek - 1,
                        startPeriod = periods.first(),
                        endPeriod = periods.last(),
                    )
                }
                .forEach(::add)

            exams
                .asSequence()
                .filter { !it.date.isBefore(weekRange.startDate) && it.date.isBefore(weekRange.endDateExclusive) }
                .mapNotNull { exam ->
                    val range = TimetablePeriodSchedule.periodRange(
                        exam.startTime.hour * 60 + exam.startTime.minute,
                        exam.endTime.hour * 60 + exam.endTime.minute,
                    ) ?: return@mapNotNull null
                    RawItem(
                        stableId = "exam:${exam.id}",
                        sourceId = exam.id,
                        type = TimetableGridItemType.EXAM,
                        title = exam.name,
                        subtitle = exam.location.ifBlank { null },
                        dayIndex = ChronoUnit.DAYS.between(weekRange.startDate, exam.date).toInt(),
                        startPeriod = range.first,
                        endPeriod = range.last,
                    )
                }
                .forEach(::add)

            scheduleEvents.mapNotNull { event ->
                val start = Instant.ofEpochMilli(event.startsAt).atZone(campusZone)
                val date = start.toLocalDate()
                if (date.isBefore(weekRange.startDate) || !date.isBefore(weekRange.endDateExclusive)) {
                    return@mapNotNull null
                }
                val end = event.endsAt
                    ?.takeIf { it > event.startsAt }
                    ?.let { Instant.ofEpochMilli(it).atZone(campusZone) }
                    ?: start.plusMinutes(45)
                val endMinutes = if (end.toLocalDate() == date) {
                    end.hour * 60 + end.minute
                } else {
                    TimetablePeriodSchedule.slots.last().endMinutes
                }
                val range = TimetablePeriodSchedule.periodRange(
                    start.hour * 60 + start.minute,
                    endMinutes,
                ) ?: return@mapNotNull null
                RawItem(
                    stableId = "schedule:${event.id}",
                    sourceId = event.id,
                    type = TimetableGridItemType.SCHEDULE,
                    title = event.title,
                    subtitle = event.location?.takeIf(String::isNotBlank),
                    dayIndex = ChronoUnit.DAYS.between(weekRange.startDate, date).toInt(),
                    startPeriod = range.first,
                    endPeriod = range.last,
                )
            }.forEach(::add)
        }

        val projected = rawItems
            .groupBy(RawItem::dayIndex)
            .values
            .flatMap(::assignLanes)
            .sortedWith(compareBy(TimetableGridItem::dayIndex, TimetableGridItem::startPeriod, TimetableGridItem::lane))

        return TimetableGridSnapshot(weekRange = weekRange, items = projected)
    }

    private fun assignLanes(dayItems: List<RawItem>): List<TimetableGridItem> {
        val sorted = dayItems.sortedWith(
            compareBy<RawItem> { it.startPeriod }
                .thenByDescending { it.endPeriod }
                .thenBy { it.stableId },
        )
        val result = mutableListOf<TimetableGridItem>()
        var index = 0
        while (index < sorted.size) {
            val cluster = mutableListOf<RawItem>()
            var clusterEnd = sorted[index].endPeriod
            do {
                val item = sorted[index]
                cluster += item
                clusterEnd = maxOf(clusterEnd, item.endPeriod)
                index += 1
            } while (index < sorted.size && sorted[index].startPeriod <= clusterEnd)

            val laneEnds = mutableListOf<Int>()
            val assigned = cluster.map { item ->
                val lane = laneEnds.indexOfFirst { it < item.startPeriod }
                    .takeIf { it >= 0 }
                    ?: laneEnds.size
                if (lane == laneEnds.size) laneEnds += item.endPeriod else laneEnds[lane] = item.endPeriod
                item to lane
            }
            val laneCount = laneEnds.size.coerceAtLeast(1)
            result += assigned.map { (item, lane) ->
                TimetableGridItem(
                    stableId = item.stableId,
                    sourceId = item.sourceId,
                    type = item.type,
                    title = item.title,
                    subtitle = item.subtitle,
                    dayIndex = item.dayIndex,
                    startPeriod = item.startPeriod,
                    periodSpan = item.endPeriod - item.startPeriod + 1,
                    lane = lane,
                    laneCount = laneCount,
                )
            }
        }
        return result
    }

    private data class RawItem(
        val stableId: String,
        val sourceId: String,
        val type: TimetableGridItemType,
        val title: String,
        val subtitle: String?,
        val dayIndex: Int,
        val startPeriod: Int,
        val endPeriod: Int,
    )
}
