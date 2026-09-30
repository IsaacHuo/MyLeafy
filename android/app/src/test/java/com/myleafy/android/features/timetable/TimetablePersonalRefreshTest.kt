package com.myleafy.android.features.timetable

import com.myleafy.android.core.data.local.*
import org.junit.Assert.*
import org.junit.Test

class TimetablePersonalRefreshTest {
    private val old = CourseEntity("test", "old", "2026-2027-1", "课程", "教师甲", "班级", "702", "二教", 1, listOf(1, 2, 3, 4), listOf(6, 7))
    private val note = CourseNoteEntity("test", old.sourceSemesterID, old.stableCourseKey(), 0, "作业")
    private val reminder = CourseReminderEntity("test", old.sourceSemesterID, old.stableCourseKey(), 20, 6)
    @Test fun recordIdAndWeekChangesPreserveDataButRemovedOccurrenceBecomesPending() {
        val next = old.copy(id = "fresh", weeks = listOf(1, 2))
        val result = TimetablePersonalRefresh.prepare(listOf(old), listOf(next), listOf(note, note.copy(week = 4)), listOf(reminder))
        assertFalse(result.notes.first { it.week == 0 }.orphaned)
        assertTrue(result.notes.first { it.week == 4 }.orphaned)
        assertFalse(result.reminders.single().orphaned)
    }
    @Test fun teacherSplitCopiesWholeCourseAndMovesOccurrenceToItsActualWeek() {
        val a = old.copy(teacher = "教师乙", weeks = listOf(1, 2))
        val b = old.copy(teacher = "教师丙", weeks = listOf(3, 4))
        val result = TimetablePersonalRefresh.prepare(listOf(old), listOf(a, b), listOf(note, note.copy(week = 4)), listOf(reminder))
        assertEquals(setOf(a.stableCourseKey(), b.stableCourseKey()), result.notes.filter { !it.orphaned && it.week == 0 }.map { it.courseKey }.toSet())
        assertEquals(b.stableCourseKey(), result.notes.single { !it.orphaned && it.week == 4 }.courseKey)
        assertEquals(2, result.reminders.count { !it.orphaned })
    }
    @Test fun ambiguousOrConflictingAssociationsStopBeforeReplacement() {
        val a = old.copy(teacher = "教师乙")
        val b = old.copy(teacher = "教师丙")
        assertThrows(IllegalStateException::class.java) { TimetablePersonalRefresh.prepare(listOf(old), listOf(a, b), listOf(note.copy(week = 2)), emptyList()) }
        assertThrows(IllegalStateException::class.java) { TimetablePersonalRefresh.prepare(listOf(old), listOf(a), listOf(note, note.copy(courseKey = a.stableCourseKey(), text = "不同备注")), emptyList()) }
    }
}
