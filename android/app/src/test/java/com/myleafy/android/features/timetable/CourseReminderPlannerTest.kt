package com.myleafy.android.features.timetable

import com.myleafy.android.core.data.local.*
import com.myleafy.android.features.timetable.domain.SemesterRuntimeConfig
import com.myleafy.android.features.timetable.presentation.compactWeeks
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class CourseReminderPlannerTest {
    private val config = SemesterRuntimeConfig.builtIn
    private val course = CourseEntity("test", "changing-record-id", config.semesterId, "电气测量", "教师", "", "", "二教702", 1, listOf(1, 3, 3, 5), listOf(6, 7))
    private val reminder = CourseReminderEntity("test", config.semesterId, course.stableCourseKey(), 20, 6)
    @Test fun schedulesActualWeeksOnceUsingSelectedPeriodAndCampusTime() {
        val alarms = CourseReminderPlanner.alarms(listOf(course), listOf(reminder), config, Instant.parse("2026-09-01T00:00:00Z"))
        assertEquals(listOf(1, 3, 5), alarms.map { it.week })
        assertEquals(Instant.parse("2026-09-07T05:10:00Z"), alarms.first().firesAt)
        assertEquals(1200, (alarms.first().startsAt.epochSecond - alarms.first().firesAt.epochSecond).toInt())
        assertEquals(alarms.map { it.id }, CourseReminderPlanner.alarms(listOf(course.copy(id = "new")), listOf(reminder), config, Instant.parse("2026-09-01T00:00:00Z")).map { it.id })
    }
    @Test fun expiredDisabledOrOrphanedRemindersDoNotSchedule() {
        assertTrue(CourseReminderPlanner.alarms(listOf(course), listOf(reminder.copy(orphaned = true)), config, Instant.EPOCH).isEmpty())
        assertTrue(CourseReminderPlanner.alarms(listOf(course), listOf(reminder.copy(minutes = 0)), config, Instant.EPOCH).isEmpty())
        assertTrue(CourseReminderPlanner.alarms(listOf(course), listOf(reminder), config, Instant.parse("2027-01-01T00:00:00Z")).isEmpty())
        assertEquals("第1–3、5、7–8周", compactWeeks(listOf(1, 2, 3, 5, 7, 8)))
    }
}
