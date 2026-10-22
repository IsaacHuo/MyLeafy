package com.myleafy.android.features.schedule

import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.features.timetable.domain.TimetableGridProjection
import java.time.LocalDateTime
import org.junit.Assert.assertEquals
import org.junit.Test

/** 日迹日程卡片的倒计时与日期文案（纯本地格式化，不依赖 Android 框架）。 */
class ScheduleTimeLabelsTest {

    private val zone = TimetableGridProjection.campusZone

    @Test
    fun countdownUnderOneMinuteDoesNotShowZeroHoursAndMinutes() {
        val now = millis(2026, 10, 22, 9, 0)

        assertEquals("即将开始", ScheduleCountdown.description(now + 45_000, now))
        assertEquals("即将开始", ScheduleCountdown.description(now + 59_999, now))
    }

    @Test
    fun countdownKeepsHourAndMinuteLabels() {
        val now = millis(2026, 10, 22, 9, 0)

        assertEquals("还有 0 小时 1 分钟", ScheduleCountdown.description(now + 60_000, now))
        assertEquals("还有 2 小时 30 分钟", ScheduleCountdown.description(now + 150 * 60_000, now))
        assertEquals("还有 1 天 2 小时", ScheduleCountdown.description(now + 26 * 60 * 60_000, now))
    }

    @Test
    fun countdownReportsStartedForPastOrCurrentMoment() {
        val now = millis(2026, 10, 22, 9, 0)

        assertEquals("已开始", ScheduleCountdown.description(now - 1, now))
        assertEquals("已开始", ScheduleCountdown.description(now, now))
    }

    @Test
    fun eventTimeKeepsShortFormInsideCurrentYear() {
        val event = event(2026, 3, 5, 9, 0, endHour = 10, endMinute = 30)

        assertEquals(
            "3月5日 09:00–10:30",
            formatEventTime(event, millis(2026, 10, 22, 12, 0)),
        )
    }

    @Test
    fun eventTimeAddsYearForOtherYears() {
        val past = event(2025, 3, 5, 9, 0, endHour = 10, endMinute = 30)
        val future = event(2027, 12, 31, 20, 0, endHour = 22, endMinute = 0)
        val now = millis(2026, 10, 22, 12, 0)

        assertEquals("2025年3月5日 09:00–10:30", formatEventTime(past, now))
        assertEquals("2027年12月31日 20:00–22:00", formatEventTime(future, now))
    }

    private fun millis(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long =
        LocalDateTime.of(year, month, day, hour, minute).atZone(zone).toInstant().toEpochMilli()

    private fun event(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        endHour: Int,
        endMinute: Int,
    ) = ScheduleEventEntity(
        scopeKey = "scope",
        id = "event-$year-$month-$day",
        title = "日程",
        startsAt = millis(year, month, day, hour, minute),
        endsAt = millis(year, month, day, endHour, endMinute),
        location = null,
        note = null,
        minutesBefore = 0,
    )
}
