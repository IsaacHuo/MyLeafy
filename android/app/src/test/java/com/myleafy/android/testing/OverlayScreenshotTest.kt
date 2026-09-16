package com.myleafy.android.testing

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.schedule.MemoDraft
import com.myleafy.android.features.schedule.MemoEditorSheet
import com.myleafy.android.features.schedule.ScheduleEventDraft
import com.myleafy.android.features.schedule.ScheduleEventEditorSheet
import com.myleafy.android.features.schedule.ScheduleMutationState
import com.myleafy.android.features.timetable.presentation.CourseDetailsDialog
import com.myleafy.android.features.timetable.presentation.ExamDetailsDialog
import java.time.LocalDate
import java.time.LocalTime
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Dialog and bottom-sheet goldens.
 *
 * Roborazzi detects the extra dialog window and composites the whole screen, so
 * these captures include the scrim and the page behind the overlay. The harness
 * also proves the overlays can actually be opened from their stateless entries.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class OverlayScreenshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun courseDetailsDialogLongNameLight() {
        composeRule.setContent {
            LeafyScreenshotTheme {
                CourseDetailsDialog(
                    course = courseEntity(courseName = ScreenshotData.LONG_COURSE_TITLE),
                    onDismiss = {},
                )
            }
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithText(ScreenshotData.LONG_COURSE_TITLE).assertIsDisplayed()
        capture()
    }

    @Test
    fun examDetailsDialogDarkFontScale130() {
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = true, fontScale = 1.3f) {
                ExamDetailsDialog(
                    exam = examEntity(name = "森林生态学野外综合实习（含群落调查）"),
                    onDismiss = {},
                )
            }
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithText("日期").assertIsDisplayed()
        capture()
    }

    @Test
    fun memoEditorSheetLight() {
        composeRule.setContent {
            LeafyScreenshotTheme {
                MemoEditorSheet(
                    initial = MemoDraft(
                        id = null,
                        title = "野外实习准备",
                        body = "带上记录本、放大镜与备用电池，周五 8:00 在一教集合。",
                        tags = listOf("学习", "实验"),
                    ),
                    mutationState = ScheduleMutationState.Idle,
                    onSave = {},
                    onDelete = null,
                    onConsumeMutation = {},
                    onDismiss = {},
                )
            }
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithText("新建随记").assertIsDisplayed()
        capture()
    }

    @Test
    fun scheduleEventEditorSheetDark() {
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = true) {
                ScheduleEventEditorSheet(
                    initial = eventDraft(id = null),
                    mutationState = ScheduleMutationState.Idle,
                    onSave = {},
                    onDelete = null,
                    onConsumeMutation = {},
                    onDismiss = {},
                )
            }
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithText("添加个人日程").assertIsDisplayed()
        capture()
    }

    /** Sheet plus a nested confirmation dialog: two overlay windows at once. */
    @Test
    fun scheduleEventDeleteConfirmLight() {
        composeRule.setContent {
            LeafyScreenshotTheme {
                ScheduleEventEditorSheet(
                    initial = eventDraft(id = "event-1"),
                    mutationState = ScheduleMutationState.Idle,
                    onSave = {},
                    onDelete = {},
                    onConsumeMutation = {},
                    onDismiss = {},
                )
            }
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithText("删除").performScrollTo().performClick()
        composeRule.onNodeWithText("删除这条日程？").assertIsDisplayed()
        capture()
    }

    private fun eventDraft(id: String?) = ScheduleEventDraft(
        id = id,
        title = "答辩准备",
        date = LocalDate.of(2026, 9, 11),
        startsAt = LocalTime.of(8, 0),
        endsAt = LocalTime.of(9, 30),
        location = "二教 305",
        note = "带上实验记录本与打印稿",
    )

    private fun capture() = composeRule.onRoot().captureRoboImage()
}
