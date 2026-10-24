package com.myleafy.android.features.timetable

import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import com.myleafy.android.features.timetable.domain.TimetableUserSettings
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TimetableUserSettingsTest {
    @Test
    fun defaultSettingsAreValidAndFixedToTwentyWeeks() {
        val settings = TimetableUserSettings()

        assertTrue(settings.isValid)
        assertEquals("2026–2027 学年 · 第 1 学期", settings.summary)
        assertEquals(13, settings.periodCount)
    }

    @Test
    fun nonMondayStartIsNormalizedToPreviousMonday() {
        val sunday = LocalDate.of(2026, 9, 13)

        assertEquals(LocalDate.of(2026, 9, 7), TimetableUserSettings.mondayOf(sunday))
    }

    @Test
    fun periodCountCanGrowToTwentyFourAndShrinkAgain() {
        val expanded = TimetableUserSettings().withPeriodCount(24)
        assertEquals(24, expanded.periodCount)
        assertTrue(expanded.isValid)
        assertEquals(24, expanded.periods.last().period)

        val reduced = expanded.withPeriodCount(5)
        assertEquals(5, reduced.periodCount)
        assertTrue(reduced.isValid)
    }

    @Test
    fun overlappingPeriodsAreRejected() {
        val settings = TimetableUserSettings().copy(
            periods = listOf(
                TimetablePeriodSchedule.Slot(1, 8, 0, 8, 45),
                TimetablePeriodSchedule.Slot(2, 8, 30, 9, 15),
            ),
        )

        assertFalse(settings.isValid)
        assertEquals("第 2 节与上一节时间重叠", settings.validationError)
    }

    @Test
    fun startMustBeBeforeEnd() {
        val settings = TimetableUserSettings().copy(
            periods = listOf(TimetablePeriodSchedule.Slot(1, 9, 0, 8, 45)),
        )

        assertFalse(settings.isValid)
        assertEquals("第 1 节开始时间必须早于结束时间", settings.validationError)
    }
}
