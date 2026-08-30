package com.myleafy.android.features.timetable.domain

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TimetableGridProjectionTest {
    private val week = TimetableWeekRange(week = 2, startDate = LocalDate.of(2026, 9, 14))

    @Test
    fun courseSpanUsesFirstAndLastActualPeriod() {
        val snapshot = TimetableGridProjection.project(
            courses = listOf(course(id = "a", periods = listOf(1, 2, 4))),
            exams = emptyList(),
            scheduleEvents = emptyList(),
            weekRange = week,
        )

        assertEquals(1, snapshot.items.single().startPeriod)
        assertEquals(4, snapshot.items.single().periodSpan)
    }

    @Test
    fun overlappingItemsReceiveParallelLanesAndIndependentClusterResets() {
        val snapshot = TimetableGridProjection.project(
            courses = listOf(
                course(id = "a", periods = listOf(1, 2)),
                course(id = "b", periods = listOf(2, 3)),
                course(id = "c", periods = listOf(5, 6)),
            ),
            exams = emptyList(),
            scheduleEvents = emptyList(),
            weekRange = week,
        )

        val firstCluster = snapshot.items.filter { it.startPeriod <= 2 }
        assertEquals(setOf(0, 1), firstCluster.map { it.lane }.toSet())
        assertTrue(firstCluster.all { it.laneCount == 2 })
        val independent = snapshot.items.single { it.sourceId == "c" }
        assertEquals(0, independent.lane)
        assertEquals(1, independent.laneCount)
    }

    @Test
    fun examAndScheduleUseShanghaiWeekAndPeriodRanges() {
        val scheduleStart = LocalDateTime.of(2026, 9, 16, 9, 55)
            .atZone(TimetableGridProjection.campusZone)
            .toInstant()
            .toEpochMilli()
        val snapshot = TimetableGridProjection.project(
            courses = emptyList(),
            exams = listOf(
                TimetableGridExam(
                    id = "exam-1",
                    name = "高等数学考试",
                    location = "二教 201",
                    date = LocalDate.of(2026, 9, 16),
                    startTime = LocalTime.of(9, 50),
                    endTime = LocalTime.of(11, 25),
                ),
            ),
            scheduleEvents = listOf(
                TimetableGridScheduleEvent(
                    id = "event-1",
                    title = "小组讨论",
                    location = "图书馆",
                    startsAt = scheduleStart,
                    endsAt = scheduleStart + 45 * 60 * 1000,
                ),
            ),
            weekRange = week,
        )

        assertEquals(2, snapshot.items.size)
        assertTrue(snapshot.items.all { it.dayIndex == 2 })
        assertEquals(2, snapshot.items.single { it.type == TimetableGridItemType.EXAM }.periodSpan)
        assertEquals(2, snapshot.items.map { it.laneCount }.max())
    }

    private fun course(id: String, periods: List<Int>) = TimetableGridCourse(
        id = id,
        name = id,
        teacher = "教师",
        location = "一教",
        room = "101",
        dayOfWeek = 3,
        weeks = listOf(2),
        periods = periods,
    )
}
