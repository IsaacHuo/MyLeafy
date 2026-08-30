package com.myleafy.android.features.timetable.export

import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TimetableCalendarExporterTest {
    private val exporter = TimetableCalendarExporter(
        Clock.fixed(Instant.parse("2026-08-30T00:00:00Z"), ZoneOffset.UTC),
    )

    @Test
    fun expandsCourseWeeksAndIncludesPersonalSchedulesInShanghaiTime() {
        val scheduleStart = Instant.parse("2026-09-16T02:00:00Z").toEpochMilli()
        val text = exporter.render(
            semesterId = "2026-2027-1",
            semesterStartDate = LocalDate.of(2026, 9, 7),
            rangeStart = LocalDate.of(2026, 9, 7),
            rangeEndExclusive = LocalDate.of(2026, 9, 28),
            courses = listOf(
                CalendarExportCourse(
                    id = "course-1",
                    title = "森林生态学",
                    teacher = "张老师",
                    classInfo = "林学 1 班",
                    location = "一教",
                    room = "101",
                    dayOfWeek = 3,
                    weeks = listOf(1, 2, 4),
                    periods = listOf(3, 4),
                ),
            ),
            scheduleEvents = listOf(
                CalendarExportScheduleEvent(
                    id = "event-1",
                    title = "小组讨论",
                    startsAt = scheduleStart,
                    endsAt = scheduleStart + 60 * 60 * 1000,
                    location = "图书馆",
                    note = "带电脑",
                ),
            ),
        )

        assertTrue(text.contains("UID:course-course-1-week-1@myleafy.android"))
        assertTrue(text.contains("UID:course-course-1-week-2@myleafy.android"))
        assertFalse(text.contains("week-4@myleafy.android"))
        assertTrue(text.contains("DTSTART;TZID=Asia/Shanghai:20260916T100000"))
        assertTrue(text.contains("UID:schedule-event-1@myleafy.android"))
    }

    @Test
    fun escapesTextAndFoldsEveryPhysicalLineTo75Utf8Octets() {
        val text = exporter.render(
            semesterId = "2026-2027-1",
            semesterStartDate = LocalDate.of(2026, 9, 7),
            rangeStart = LocalDate.of(2026, 9, 7),
            rangeEndExclusive = LocalDate.of(2026, 9, 14),
            courses = emptyList(),
            scheduleEvents = listOf(
                CalendarExportScheduleEvent(
                    id = "event-2",
                    title = "讨论,复盘;总结\\归档",
                    startsAt = Instant.parse("2026-09-08T01:00:00Z").toEpochMilli(),
                    endsAt = Instant.parse("2026-09-08T02:00:00Z").toEpochMilli(),
                    location = "图书馆",
                    note = "第一行\n" + "很长的中文备注".repeat(12),
                ),
            ),
        )

        assertTrue(text.contains("SUMMARY:讨论\\,复盘\\;总结\\\\归档"))
        assertTrue(text.contains("DESCRIPTION:第一行\\n"))
        assertTrue(text.split("\r\n").filter(String::isNotEmpty).all {
            it.toByteArray(Charsets.UTF_8).size <= 75
        })
    }
}
