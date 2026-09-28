package com.myleafy.android.testing

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
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
    fun adjacentConflictCardsKeepIndependentTouchBounds() {
        var selected: String? = null
        render(showWeekends = true, darkTheme = false, fontScale = 1.4f, gridHeight = 480.dp,
            onItemClick = { selected = it.sourceId })
        composeRule.onNodeWithTag("timetable-item-course::math::1").performTouchInput { click(centerRight - androidx.compose.ui.geometry.Offset(1f, 0f)) }
        composeRule.runOnIdle { assertEquals("math", selected) }
        composeRule.onNodeWithTag("timetable-item-course::lab::1").performTouchInput { click(centerLeft + androidx.compose.ui.geometry.Offset(1f, 0f)) }
        composeRule.runOnIdle { assertEquals("lab", selected) }
    }

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

        // 这一格必须是真的空格子：周一 1-2 节有课程块盖在上面，
        // 点它会命中课程卡而不是空格回调，测不出空格交互。
        composeRule.onNodeWithTag("timetable-cell-2026-09-09-1").performClick()
        composeRule.runOnIdle {
            assertEquals(ScreenshotData.day(2), clickedDate)
            assertEquals(1, clickedPeriod)
        }

        composeRule.onNodeWithTag("timetable-item-course::forest::1").performClick()
        composeRule.runOnIdle { assertEquals("forest", clickedItem?.sourceId) }

        composeRule.onNodeWithContentDescription("森林生态学", substring = true).assertExists()
        // 极限字体下时间轴不能把 08:00 掐成 08:…：轴宽随 fontScale 放大，
        // 开始时间仍然完整；行高放不下结束时间时整段区间由语义承载。
        assertAxisStartTimesFit()
        assertAxisEndTimesFit(requireAll = false)
        composeRule.onNodeWithContentDescription("第1节，08:00 至 08:45").assertExists()
        capture()
    }

    /**
     * 真实可用高度：360dp 宽的手机减去顶栏、周次头与底部导航后，网格大约只剩 480dp。
     * 这里按这个高度渲染，验证 13 节的起止时间全部可读，而不是只在 800dp 高的
     * 满屏网格上验收。
     */
    @Test
    fun weekdaysSmallHeightGridTimesVisible() {
        var clickedDate: LocalDate? = null
        render(
            showWeekends = false,
            darkTheme = false,
            gridHeight = 480.dp,
            onEmptyCellClick = { date, _ -> clickedDate = date },
        )

        assertAxisStartTimesFit()
        // 默认字体下 13 节的结束时间也必须全部显示，不能只留开始时间。
        assertAxisEndTimesFit(requireAll = true)
        composeRule.onNodeWithContentDescription("第1节，08:00 至 08:45").assertExists()
        composeRule.onNodeWithTag("timetable-item-course::forest::1").assertIsDisplayed()
        composeRule.onNodeWithTag("timetable-cell-2026-09-09-1").performClick()
        composeRule.runOnIdle { assertEquals(ScreenshotData.day(2), clickedDate) }
        capture()
    }

    /** 真机默认字体放大倍率（font_scale = 1.4）下的同一组检查。 */
    @Test
    fun weekdaysSmallHeightFontScale140TimesVisible() {
        render(showWeekends = false, darkTheme = false, fontScale = 1.4f, gridHeight = 480.dp)

        assertAxisStartTimesFit()
        assertAxisEndTimesFit(requireAll = false)
        composeRule.onNodeWithContentDescription("第13节，21:00 至 21:45").assertExists()
        capture()
    }

    @Test
    fun stackedAxisWithPhoneHeightKeepsBothTimesAt140Percent() {
        render(showWeekends = true, darkTheme = false, fontScale = 1.4f, gridHeight = 620.dp)
        assertAxisStartTimesFit()
        assertAxisEndTimesFit(requireAll = true)
        val period = composeRule.onNodeWithTag("timetable-axis-period-1", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val start = composeRule.onNodeWithTag("timetable-axis-start-1", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        org.junit.Assert.assertTrue(period.bottom <= start.top + 1f)
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
        gridHeight: Dp? = null,
        onEmptyCellClick: (LocalDate, Int) -> Unit = { _, _ -> },
        onItemClick: (TimetableGridItem) -> Unit = {},
    ) {
        val snapshot = weekOneSnapshot(longNames)
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = darkTheme, fontScale = fontScale) {
                // gridHeight 用来模拟“顶栏 + 周次头 + 底部导航”之后剩下的真实网格高度。
                Column(modifier = Modifier.fillMaxSize()) {
                    TimetableGrid(
                        snapshot = snapshot,
                        onEmptyCellClick = onEmptyCellClick,
                        onItemClick = onItemClick,
                        modifier = if (gridHeight == null) {
                            Modifier.fillMaxSize()
                        } else {
                            Modifier.fillMaxWidth().height(gridHeight)
                        },
                        today = ScreenshotData.day(1),
                        currentTime = LocalTime.of(9, 10),
                        showWeekends = showWeekends,
                    )
                }
            }
        }
        composeRule.waitForIdle()
    }

    /** 13 节的开始时间在任何字体下都必须完整显示，且没有被截断。 */
    private fun assertAxisStartTimesFit() {
        for (period in 1..13) {
            // 轴格整体合并成一个无障碍节点（“第N节，开始 至 结束”），
            // 因此格子里的起止时间只存在于 unmerged 语义树里。
            composeRule
                .onNodeWithTag("timetable-axis-start-$period", useUnmergedTree = true)
                .assertIsDisplayed()
                .assertTextLayoutFits()
        }
    }

    /**
     * 结束时间：存在时必须在屏幕内且不被截断；行高放不下时该行只显示开始时间，
     * 完整区间仍由合并语义提供。[requireAll] 用来区分“必须全部显示”与“允许省略”。
     */
    private fun assertAxisEndTimesFit(requireAll: Boolean) {
        val omitted = mutableListOf<Int>()
        for (period in 1..13) {
            val tag = "timetable-axis-end-$period"
            val present = composeRule
                .onAllNodesWithTag(tag, useUnmergedTree = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
            if (!present) {
                omitted += period
                continue
            }
            composeRule
                .onNodeWithTag(tag, useUnmergedTree = true)
                .assertIsDisplayed()
                .assertTextLayoutFits()
        }
        if (requireAll) {
            assertEquals("结束时间被省略的节次=$omitted", emptyList<Int>(), omitted)
        }
    }

    private fun capture() = composeRule.onRoot().captureRoboImage()
}
