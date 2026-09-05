package com.myleafy.android.features.timetable.presentation

import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.test.platform.app.InstrumentationRegistry
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.features.timetable.domain.TimetableGridItem
import com.myleafy.android.features.timetable.domain.TimetableGridItemType
import com.myleafy.android.features.timetable.domain.TimetableGridSnapshot
import com.myleafy.android.features.timetable.domain.TimetableWeekRange
import com.myleafy.android.ui.theme.MyLeafyTheme
import java.time.LocalDate
import java.time.LocalTime
import java.io.File
import java.io.FileOutputStream
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

        composeRule.onNodeWithTag("timetable-cell-2026-09-07-3")
            .performClick()
        composeRule.runOnIdle { assertEquals(weekStart to 3, clickedCell) }

        composeRule.onNodeWithTag("timetable-grid")
            .assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.VerticalScrollAxisRange))
    }

    @Test
    fun currentWeekExposesAReadableCurrentTimeIndicator() {
        val weekStart = LocalDate.of(2026, 9, 7)
        composeRule.setContent {
            MyLeafyTheme(darkTheme = true) {
                TimetableGrid(
                    snapshot = TimetableGridSnapshot(
                        weekRange = TimetableWeekRange(week = 1, startDate = weekStart),
                        items = emptyList(),
                    ),
                    onEmptyCellClick = { _, _ -> },
                    onItemClick = {},
                    modifier = Modifier.fillMaxSize(),
                    today = weekStart.plusDays(1),
                    currentTime = LocalTime.of(9, 10),
                )
            }
        }

        composeRule.onNodeWithTag("timetable-current-time").assertIsDisplayed()
        composeRule.onNode(hasContentDescription("当前时间")).assertIsDisplayed()
    }

    @Test
    fun hidingWeekendsUsesFiveColumnsWithoutDeletingWeekdayCells() {
        val weekStart = LocalDate.of(2026, 9, 7)
        composeRule.setContent {
            MyLeafyTheme(darkTheme = false) {
                TimetableGrid(
                    snapshot = TimetableGridSnapshot(
                        weekRange = TimetableWeekRange(week = 1, startDate = weekStart),
                        items = emptyList(),
                    ),
                    onEmptyCellClick = { _, _ -> },
                    onItemClick = {},
                    modifier = Modifier.fillMaxSize(),
                    showWeekends = false,
                )
            }
        }

        composeRule.onNodeWithTag("timetable-cell-2026-09-11-1").assertExists()
        composeRule.onNodeWithTag("timetable-cell-2026-09-12-1").assertDoesNotExist()
    }

    @Test
    fun removingPhotoBackgroundDoesNotRecycleABitmapStillOwnedByCompose() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val photo = File(context.cacheDir, "timetable-background-lifecycle.png")
        Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888).also { bitmap ->
            bitmap.eraseColor(Color.GREEN)
            FileOutputStream(photo).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
        var showPhoto by mutableStateOf(true)

        try {
            composeRule.setContent {
                MyLeafyTheme {
                    TimetableGrid(
                        snapshot = TimetableGridSnapshot(
                            weekRange = TimetableWeekRange(1, LocalDate.of(2026, 9, 7)),
                            items = emptyList(),
                        ),
                        onEmptyCellClick = { _, _ -> },
                        onItemClick = {},
                        modifier = Modifier.fillMaxSize(),
                        background = if (showPhoto) {
                            TimetableBackgroundSettings(enabled = true, kind = "photo", photoPath = photo.absolutePath)
                        } else {
                            TimetableBackgroundSettings()
                        },
                    )
                }
            }
            composeRule.waitForIdle()
            composeRule.runOnUiThread { showPhoto = false }
            composeRule.waitForIdle()
            composeRule.runOnUiThread { showPhoto = true }
            composeRule.waitForIdle()
            composeRule.onNodeWithTag("timetable-grid").assertIsDisplayed()
        } finally {
            photo.delete()
        }
    }
}
