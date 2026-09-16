package com.myleafy.android.testing

import android.app.Application
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.campus.CampusDashboard
import com.myleafy.android.features.campus.CampusSyncState
import com.myleafy.android.features.campus.CampusUiState
import com.myleafy.android.features.schedule.ScheduleContent
import com.myleafy.android.features.schedule.ScheduleSection
import com.myleafy.android.features.schedule.notifications.ScheduleReportsUiState
import com.myleafy.android.navigation.FeatureDestination
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Root page bodies that already expose a stateless entry point: 日迹 and 校园.
 * The chrome around them is covered by [RootShellScreenshotTest]; the screens that
 * still bind a ViewModel are noted in the hand-off instead of being faked here.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class RootContentScreenshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun scheduleEmptyLight() {
        composeRule.setContent {
            LeafyScreenshotTheme {
                ScheduleContent(
                    section = ScheduleSection.EVENTS,
                    memos = emptyList(),
                    events = emptyList(),
                    onNewMemo = {}, onMemoClick = {}, onNewEvent = {}, onEventClick = {},
                    onFeatureClick = {}, reportsState = ScheduleReportsUiState(),
                    notificationPermissionDenied = false, onToggleReport = { _, _ -> },
                    onSetEventReminder = { _, _, _ -> },
                )
            }
        }
        composeRule.waitForIdle()
        capture()
    }

    @Test
    fun scheduleEmptyDark() {
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = true) {
                ScheduleContent(
                    section = ScheduleSection.EVENTS,
                    memos = emptyList(),
                    events = emptyList(),
                    onNewMemo = {}, onMemoClick = {}, onNewEvent = {}, onEventClick = {},
                    onFeatureClick = {}, reportsState = ScheduleReportsUiState(),
                    notificationPermissionDenied = false, onToggleReport = { _, _ -> },
                    onSetEventReminder = { _, _, _ -> },
                )
            }
        }
        composeRule.waitForIdle()
        capture()
    }

    @Test
    fun scheduleMemosLight() {
        var newMemoClicks = 0
        composeRule.setContent {
            LeafyScreenshotTheme {
                ScheduleContent(
                    section = ScheduleSection.MEMOS,
                    memos = listOf(
                        memoEntity("memo-1", "野外实习准备", "带上记录本、放大镜与备用电池。", pinnedAt = 1L),
                        memoEntity("memo-2", null, "周五前把实验报告写完，交给助教。"),
                    ),
                    events = emptyList(),
                    onNewMemo = { newMemoClicks += 1 },
                    onMemoClick = {}, onNewEvent = {}, onEventClick = {},
                    onFeatureClick = {}, reportsState = ScheduleReportsUiState(),
                    notificationPermissionDenied = false, onToggleReport = { _, _ -> },
                    onSetEventReminder = { _, _, _ -> },
                )
            }
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithText("新建随记").assertIsDisplayed().performClick()
        composeRule.runOnIdle { assertTrue(newMemoClicks == 1) }
        capture()
    }

    @Test
    fun campusCompactLight() = captureCampus(emptyCampusState())

    @Test
    @Config(sdk = [36], qualifiers = "w700dp-h900dp-xxhdpi", application = Application::class)
    fun campusMediumLight() = captureCampus(emptyCampusState())

    @Test
    @Config(sdk = [36], qualifiers = "w840dp-h900dp-xxhdpi", application = Application::class)
    fun campusWide840Dark() = captureCampus(loadedCampusState(), darkTheme = true)

    /**
     * 600dp + 200% font: the sidebar layout has a single scrollable region, so the
     * last feature card must still be reachable and clickable.
     */
    @Test
    @Config(sdk = [36], qualifiers = "w600dp-h900dp-xxhdpi", application = Application::class)
    fun campusWide600FontScale200Reachability() {
        var destination: FeatureDestination? = null
        composeRule.setContent {
            LeafyScreenshotTheme(fontScale = 2f) {
                CampusDashboard(
                    state = loadedCampusState(),
                    syncState = CampusSyncState.Idle,
                    onConsumeSync = {},
                    onGradesClick = {},
                    onExamsClick = {},
                    onClassroomClick = {},
                    onFeatureClick = { destination = it },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        composeRule.waitForIdle()

        composeRule
            .onNode(hasScrollAction())
            .performScrollToNode(hasText("校历"))
        composeRule.onNodeWithText("校历").assertIsDisplayed().performClick()
        composeRule.runOnIdle { assertEquals(FeatureDestination.CAMPUS_CALENDAR, destination) }
        capture()
    }

    private fun emptyCampusState() = CampusUiState.Loaded(
        terms = emptyList(),
        grades = emptyList(),
        rankings = emptyList(),
        gradeSummary = null,
        exams = emptyList(),
    )

    private fun loadedCampusState() = CampusUiState.Loaded(
        terms = listOf("2025-2026-2", "2025-2026-1"),
        grades = listOf(
            gradeEntity("g1", "森林生态学", credit = "3.0", score = "92"),
            gradeEntity("g2", "高等数学 B", credit = "5.0", score = "88"),
        ),
        rankings = listOf(rankingEntity()),
        gradeSummary = gradeSummary(),
        exams = listOf(examEntity(id = 1), examEntity(id = 2, name = "大学英语", date = "2026-01-15")),
    )

    private fun captureCampus(state: CampusUiState.Loaded, darkTheme: Boolean = false) {
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = darkTheme) {
                CampusDashboard(
                    state = state,
                    syncState = CampusSyncState.Idle,
                    onConsumeSync = {}, onGradesClick = {}, onExamsClick = {}, onClassroomClick = {},
                    onFeatureClick = {}, modifier = Modifier.fillMaxSize(),
                )
            }
        }
        composeRule.waitForIdle()
        capture()
    }

    private fun capture() = composeRule.onRoot().captureRoboImage()
}
