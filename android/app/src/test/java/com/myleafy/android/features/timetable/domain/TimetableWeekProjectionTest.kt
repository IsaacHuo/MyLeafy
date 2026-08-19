package com.myleafy.android.features.timetable.domain

import com.myleafy.android.core.data.local.CourseEntity
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TimetableWeekProjectionTest {

    private fun course(name: String, day: Int, weeks: List<Int>, duration: List<Int>) = CourseEntity(
        id = UUID.randomUUID().toString(),
        sourceSemesterID = "2025-2026-2",
        courseName = name,
        teacher = "teacher",
        classInfo = "",
        room = "101",
        location = "一教",
        dayOfWeek = day,
        weeks = weeks,
        duration = duration,
    )

    @Test
    fun filtersCoursesByWeek() {
        val courses = listOf(
            course("森林生态学", 1, weeks = (1..18).toList(), duration = listOf(1, 2)),
            course("数据结构", 3, weeks = (2..16).toList(), duration = listOf(3, 4)),
        )
        val week1 = TimetableWeekProjection.projectWeek(courses, week = 1)
        assertEquals(setOf(1), week1.keys)
        assertEquals(1, week1[1]?.size)

        val week2 = TimetableWeekProjection.projectWeek(courses, week = 2)
        assertEquals(setOf(1, 3), week2.keys)
        assertEquals(2, week2.values.sumOf { it.size })
    }

    @Test
    fun computesStartPeriodAndRowSpan() {
        val courses = listOf(course("高数", 1, listOf(1), duration = listOf(3, 4)))
        val cells = TimetableWeekProjection.coursesForDay(courses, week = 1, day = 1)
        assertEquals(1, cells.size)
        assertEquals(3, cells[0].startPeriod)
        assertEquals(2, cells[0].rowSpan)
    }

    @Test
    fun sortsDayCoursesByStartPeriod() {
        val courses = listOf(
            course("晚课", 1, listOf(1), duration = listOf(10, 11)),
            course("早课", 1, listOf(1), duration = listOf(1, 2)),
        )
        val cells = TimetableWeekProjection.coursesForDay(courses, week = 1, day = 1)
        assertEquals(listOf(1, 10), cells.map { it.startPeriod })
    }

    @Test
    fun noCoursesForWeekReturnsEmpty() {
        val courses = listOf(course("课程", 1, listOf(5), duration = listOf(1)))
        assertTrue(TimetableWeekProjection.projectWeek(courses, week = 1).isEmpty())
        assertTrue(TimetableWeekProjection.coursesForDay(courses, week = 1, day = 2).isEmpty())
    }
}
