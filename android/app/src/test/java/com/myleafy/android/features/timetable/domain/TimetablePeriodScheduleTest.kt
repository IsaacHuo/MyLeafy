package com.myleafy.android.features.timetable.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TimetablePeriodScheduleTest {

    @Test
    fun hasThirteenFixedSlots() {
        assertEquals(13, TimetablePeriodSchedule.slots.size)
    }

    @Test
    fun firstAndLastSlotMatchIos() {
        val first = TimetablePeriodSchedule.slot(period = 1)
        assertEquals(TimetablePeriodSchedule.Slot(1, 8, 0, 8, 45), first)

        val last = TimetablePeriodSchedule.slot(period = 13)
        assertEquals(TimetablePeriodSchedule.Slot(13, 21, 0, 21, 45), last)
    }

    @Test
    fun periodContainingMinutes() {
        assertEquals(1, TimetablePeriodSchedule.period(minutesOfDay = 8 * 60 + 30)?.period)
        assertEquals(9, TimetablePeriodSchedule.period(minutesOfDay = 16 * 60 + 40)?.period)
        // 课间不落在任何节次
        assertNull(TimetablePeriodSchedule.period(minutesOfDay = 9 * 60 + 40))
    }

    @Test
    fun periodForFocusPicksNextSlotBeforeDayStarts() {
        assertEquals(1, TimetablePeriodSchedule.periodForFocus(minutesOfDay = 0)?.period)
    }

    @Test
    fun periodRangeOverlapping() {
        // 08:00-10:30 覆盖第 1、2 节（第 3 节 09:50 开始，10:30 在其内）
        val range = TimetablePeriodSchedule.periodRange(startMinutes = 8 * 60, endMinutes = 10 * 60 + 30)
        assertEquals(1..3, range)
    }

    @Test
    fun startAndEndTextFormatting() {
        val slot = TimetablePeriodSchedule.slot(period = 6)
        assertEquals("13:30", slot?.startText)
        assertEquals("14:15", slot?.endText)
    }
}
