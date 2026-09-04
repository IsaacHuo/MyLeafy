package com.myleafy.android.features.schedule.notifications

import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleEventReminderEntity
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class ScheduleNotificationPlannerTest {
    private val zone = ZoneId.of("Asia/Shanghai")

    @Test
    fun dailyReportsUseConfiguredShanghaiTimes() {
        val now = ZonedDateTime.of(LocalDate.of(2026, 9, 7), LocalTime.of(6, 0), zone)
        val drafts = ScheduleNotificationPlanner.drafts(
            settings = listOf(
                ScheduleReportSetting(ScheduleReportMode.MORNING, true, 7, 30),
                ScheduleReportSetting(ScheduleReportMode.EVENING, true, 21, 30),
            ),
            reminders = emptyList(), courses = emptyList(), exams = emptyList(), events = emptyList(), now = now,
        )

        assertEquals(LocalTime.of(7, 30), drafts.first { it.id == "morning-2026-09-07" }.fireAt.atZone(zone).toLocalTime())
        assertEquals(LocalTime.of(21, 30), drafts.first { it.id == "evening-2026-09-07" }.fireAt.atZone(zone).toLocalTime())
    }

    @Test
    fun examCreatesSevenThreeAndOneDayReminders() {
        val now = ZonedDateTime.of(2026, 9, 10, 19, 0, 0, 0, zone)
        val exam = ExamEntity("scope", 42, "course", "森林生态学", "2026-09-18", "09:00", "11:00", "二教")
        val drafts = ScheduleNotificationPlanner.drafts(
            settings = listOf(ScheduleReportSetting(ScheduleReportMode.EXAM, true, 20, 0)),
            reminders = emptyList(), courses = emptyList(), exams = listOf(exam), events = emptyList(), now = now,
        )

        assertEquals(listOf("exam-42-7", "exam-42-3", "exam-42-1"), drafts.map { it.id })
    }

    @Test
    fun personalEventUsesStableIdAndLeadTime() {
        val now = ZonedDateTime.of(2026, 9, 7, 8, 0, 0, 0, zone)
        val startsAt = ZonedDateTime.of(2026, 9, 7, 10, 0, 0, 0, zone).toInstant().toEpochMilli()
        val event = ScheduleEventEntity("scope", "event-a", "小组讨论", startsAt, null, "图书馆", null, 0)
        val reminder = ScheduleEventReminderEntity("scope:event-a", "scope", "event-a", 30, true, 0, 0)
        val draft = ScheduleNotificationPlanner.drafts(
            settings = emptyList(), reminders = listOf(reminder), courses = emptyList(), exams = emptyList(), events = listOf(event), now = now,
        ).single()

        assertEquals("event-event-a-30", draft.id)
        assertEquals(LocalTime.of(9, 30), draft.fireAt.atZone(zone).toLocalTime())
        assertEquals("event-a", draft.eventId)
        assertNotNull(draft.body)
    }
}
