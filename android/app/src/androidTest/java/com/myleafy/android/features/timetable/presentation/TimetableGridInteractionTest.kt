package com.myleafy.android.features.timetable.presentation

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import com.myleafy.android.features.timetable.domain.TimetableGridItem
import com.myleafy.android.features.timetable.domain.TimetableGridItemType
import com.myleafy.android.features.timetable.domain.TimetableGridSnapshot
import com.myleafy.android.features.timetable.domain.TimetableWeekRange
import com.myleafy.android.ui.theme.MyLeafyTheme
import java.time.LocalDate
import java.time.LocalTime
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class TimetableGridInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun courseAndEmptyCellClicksDeliverTheirStableDomainValues() {
        val weekStart = LocalDate.of(2026, 9, 7)
        val course = TimetableGridItem(
            stableId = "course:forest:1",
            sourceId = "forest",
            type = TimetableGridItemType.COURSE,
            title = "森林生态学",
            subtitle = "一教 101",
            dayIndex = 0,
            startPeriod = 1,
            periodSpan = 2,
            lane = 0,
            laneCount = 1,
        )
        var clickedItem: TimetableGridItem? = null
        var clickedCell: Pair<LocalDate, Int>? = null

        composeRule.setContent {
            MyLeafyTheme(darkTheme = false) {
                TimetableGrid(
                    snapshot = TimetableGridSnapshot(
                        weekRange = TimetableWeekRange(week = 1, startDate = weekStart),
                        items = listOf(course),
                    ),
                    onEmptyCellClick = { date, period -> clickedCell = date to period },
                    onItemClick = { clickedItem = it },
                    modifier = Modifier.fillMaxSize(),
                    today = LocalDate.of(2026, 8, 30),
                    currentTime = LocalTime.NOON,
                )
            }
        }

        composeRule.onNodeWithTag("timetable-item-course:forest:1").performClick()
        composeRule.runOnIdle { assertEquals(course, clickedItem) }

        composeRule.onNodeWithTag("timetable-cell-2026-09-07-3").performClick()
        composeRule.runOnIdle { assertEquals(weekStart to 3, clickedCell) }
    }
}
