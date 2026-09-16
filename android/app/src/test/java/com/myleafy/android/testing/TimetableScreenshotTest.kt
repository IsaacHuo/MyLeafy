package com.myleafy.android.testing

import android.app.Application
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.timetable.domain.TimetableGridItem
import com.myleafy.android.features.timetable.presentation.TimetableGrid
import java.time.LocalDate
import java.time.LocalTime
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Timetable goldens. The grid is a single viewport, so the checks here are about
 * date-first headers, course text priority, conflict lanes and hit targets rather
 * than scrolling.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class TimetableScreenshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun sevenDaysWithTodayTimelineAndOverlap() {
        render(showWeekends = true, darkTheme = false)
        capture()
    }

    @Test
    fun weekdaysDark() {
        render(showWeekends = false, darkTheme = true)
        capture()
    }

    /** 360dp + 130% system font: long course names inside a two-column conflict. */
    @Test
    fun weekdaysLongNamesConflictFontScale130() {
        render(
            showWeekends = false,
            darkTheme = false,
            fontScale = 1.3f,
            longNames = true,
        )
        // The accessibility description keeps the full course name even when a
        // narrow conflict lane has to ellipsize the visible text.
        composeRule
            .onNodeWithContentDescription(ScreenshotData.LONG_COURSE_TITLE, substring = true)
            .assertExists()
        capture()
    }

    /**
     * 200% font scale: the grid must stay usable without compensating the system
     * font scale, so every cell and course block keeps working as a hit target.
     */
    @Test
    fun weekdaysFontScale200() {
        var clickedDate: LocalDate? = null
        var clickedPeriod: Int? = null
        var clickedItem: TimetableGridItem? = null
        render(
            showWeekends = false,
            darkTheme = false,
            fontScale = 2f,
            onEmptyCellClick = { date, period ->
                clickedDate = date
                clickedPeriod = period
            },
            onItemClick = { clickedItem = it },
        )

        composeRule.onNodeWithTag("timetable-cell-2026-09-07-1").performClick()
        composeRule.runOnIdle {
            assertEquals(ScreenshotData.monday, clickedDate)
            assertEquals(1, clickedPeriod)
        }

        composeRule.onNodeWithTag("timetable-item-course::forest::1").performClick()
        composeRule.runOnIdle { assertEquals("forest", clickedItem?.sourceId) }

        composeRule.onNodeWithContentDescription("森林生态学", substring = true).assertExists()
        capture()
    }

    @Test
    @Config(sdk = [36], qualifiers = "w600dp-h900dp-xxhdpi", application = Application::class)
    fun weekdaysMedium600Dark() {
        render(showWeekends = false, darkTheme = true)
        capture()
    }

    /**
     * Wide layout with a full week and long names: with the extra width there is no
     * reason for the course name to be ellipsized.
     */
    @Test
    @Config(sdk = [36], qualifiers = "w840dp-h900dp-xxhdpi", application = Application::class)
    fun sevenDaysWide840LongNames() {
        render(showWeekends = true, darkTheme = false, longNames = true)
        composeRule
            .onNodeWithContentDescription(ScreenshotData.LONG_COURSE_TITLE, substring = true)
            .assertIsDisplayed()
        capture()
    }

    private fun render(
        showWeekends: Boolean,
        darkTheme: Boolean,
        fontScale: Float = 1f,
        longNames: Boolean = false,
        onEmptyCellClick: (LocalDate, Int) -> Unit = { _, _ -> },
        onItemClick: (TimetableGridItem) -> Unit = {},
    ) {
        val snapshot = weekOneSnapshot(longNames)
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = darkTheme, fontScale = fontScale) {
                TimetableGrid(
                    snapshot = snapshot,
                    onEmptyCellClick = onEmptyCellClick,
                    onItemClick = onItemClick,
                    modifier = Modifier.fillMaxSize(),
                    today = ScreenshotData.day(1),
                    currentTime = LocalTime.of(9, 10),
                    showWeekends = showWeekends,
                )
            }
        }
        composeRule.waitForIdle()
    }

    private fun capture() = composeRule.onRoot().captureRoboImage()
}
