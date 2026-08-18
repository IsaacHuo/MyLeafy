package com.myleafy.android.features.timetable.domain

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Test

class SemesterConfigTest {

    @Test
    fun builtInConfigMatchesIosContract() {
        assertEquals("2025-2026-2", SemesterConfig.currentSemesterId)
        assertEquals(LocalDate.of(2026, 3, 9), SemesterConfig.startOfSemesterDate)
        assertEquals(20, SemesterConfig.supportedWeeks)
        assertEquals("46", SemesterConfig.graduateTimetableTermCode)
    }

    @Test
    fun timelineIncludesNextSemester() {
        val ids = SemesterConfig.timelineConfigurations.map { it.semesterId }
        assertEquals(listOf("2025-2026-2", "2026-2027-1"), ids)
    }

    @Test
    fun weekOneAtSemesterStart() {
        assertEquals(1, SemesterConfig.currentWeek(LocalDate.of(2026, 3, 9)))
        assertEquals(1, SemesterConfig.currentWeek(LocalDate.of(2026, 3, 15)))
    }

    @Test
    fun weekTwoFromSecondMonday() {
        assertEquals(2, SemesterConfig.currentWeek(LocalDate.of(2026, 3, 16)))
    }

    @Test
    fun weekIsClampedToCapacity() {
        // 超过 20 周后停在容量上限
        assertEquals(20, SemesterConfig.currentWeek(LocalDate.of(2026, 12, 31)))
    }

    @Test
    fun weekAndDayMapsDayOfWeekMondayToOne() {
        val monday = SemesterConfig.weekAndDay(LocalDate.of(2026, 3, 9))
        assertEquals(SemesterConfig.WeekAndDay(week = 1, day = 1), monday)

        val sunday = SemesterConfig.weekAndDay(LocalDate.of(2026, 3, 15))
        assertEquals(SemesterConfig.WeekAndDay(week = 1, day = 7), sunday)
    }

    @Test
    fun beforeSemesterStartClampsToWeekOne() {
        assertEquals(1, SemesterConfig.currentWeek(LocalDate.of(2026, 3, 1)))
    }

    @Test
    fun schoolCalendarEventVacationDetection() {
        val summer = SchoolCalendarEvent(
            id = "summer",
            title = "暑假",
            startDate = LocalDate.of(2026, 7, 27),
            endDate = LocalDate.of(2026, 9, 6),
            kind = SchoolCalendarEvent.Kind.HOLIDAY,
            academicCategory = SchoolCalendarEvent.AcademicCategory.SUMMER_BREAK,
        )
        assertEquals(true, summer.isVacation)
        assertEquals(true, summer.contains(LocalDate.of(2026, 8, 1)))
        assertEquals(false, summer.contains(LocalDate.of(2026, 9, 7)))
    }
}
