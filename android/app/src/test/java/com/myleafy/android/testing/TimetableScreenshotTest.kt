package com.myleafy.android.testing

import android.app.Application
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.timetable.domain.TimetableGridItem
import com.myleafy.android.features.timetable.domain.TimetableGridItemType
import com.myleafy.android.features.timetable.domain.TimetableGridSnapshot
import com.myleafy.android.features.timetable.domain.TimetableWeekRange
import com.myleafy.android.features.timetable.presentation.TimetableGrid
import com.myleafy.android.ui.theme.MyLeafyTheme
import java.time.LocalDate
import java.time.LocalTime
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class TimetableScreenshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test fun sevenDaysWithTodayTimelineAndOverlap() = capture(showWeekends = true, darkTheme = false)

    @Test fun weekdaysDark() = capture(showWeekends = false, darkTheme = true)

    private fun capture(showWeekends: Boolean, darkTheme: Boolean) {
        val monday = LocalDate.of(2026, 9, 7)
        val snapshot = TimetableGridSnapshot(
            weekRange = TimetableWeekRange(week = 1, startDate = monday),
            items = listOf(
                item("forest", "森林生态学", "一教 101", 0, 1, 2),
                item("math", "高等数学", "二教 305", 1, 3, 2, lane = 0, laneCount = 2),
                item("lab", "植物实验", "实验楼", 1, 3, 3, lane = 1, laneCount = 2),
                item("english", "大学英语", "学研 A206", 3, 7, 2),
                item("sport", "体育", "田径场", 4, 10, 2),
            ),
        )
        composeRule.setContent {
            MyLeafyTheme(darkTheme = darkTheme) {
                TimetableGrid(
                    snapshot = snapshot,
                    onEmptyCellClick = { _, _ -> },
                    onItemClick = {},
                    modifier = Modifier.fillMaxSize(),
                    today = monday.plusDays(1),
                    currentTime = LocalTime.of(9, 10),
                    showWeekends = showWeekends,
                )
            }
        }
        composeRule.waitForIdle()
        composeRule.onRoot().captureRoboImage()
    }

    private fun item(
        id: String,
        title: String,
        subtitle: String,
        day: Int,
        start: Int,
        span: Int,
        lane: Int = 0,
        laneCount: Int = 1,
    ) = TimetableGridItem(
        stableId = "course:$id:1",
        sourceId = id,
        type = TimetableGridItemType.COURSE,
        title = title,
        subtitle = subtitle,
        dayIndex = day,
        startPeriod = start,
        periodSpan = span,
        lane = lane,
        laneCount = laneCount,
    )
}
