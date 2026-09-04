package com.myleafy.android.features.schedule

import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.semantics.SemanticsActions
import com.myleafy.android.ui.theme.MyLeafyTheme
import java.time.LocalDate
import java.time.LocalTime
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ScheduleEventEditorSheetTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun blankTitleKeepsSaveDisabled() {
        composeRule.setContent {
            MyLeafyTheme(darkTheme = false) {
                ScheduleEventEditorSheet(
                    initial = draft(id = null, title = ""),
                    mutationState = ScheduleMutationState.Idle,
                    onSave = {},
                    onDelete = null,
                    onConsumeMutation = {},
                    onDismiss = {},
                )
            }
        }

        composeRule.onNodeWithText("请填写日程标题").assertExists()
        composeRule.onNodeWithText("保存").assertIsNotEnabled()
    }

    @Test
    fun existingEventCanBeEditedAndDeletedAfterConfirmation() {
        var saved: ScheduleEventDraft? = null
        var deletedId: String? = null
        composeRule.setContent {
            MyLeafyTheme(darkTheme = false) {
                ScheduleEventEditorSheet(
                    initial = draft(id = "event-1", title = "原日程"),
                    mutationState = ScheduleMutationState.Idle,
                    onSave = { saved = it },
                    onDelete = { deletedId = it },
                    onConsumeMutation = {},
                    onDismiss = {},
                )
            }
        }

        composeRule.onNodeWithText("标题 *").performTextReplacement("答辩准备")
        composeRule.onNodeWithText("保存").performClick()
        composeRule.runOnIdle {
            assertEquals("event-1", saved?.id)
            assertEquals("答辩准备", saved?.title)
        }

        composeRule.onNodeWithText("删除").performClick()
        composeRule.onNodeWithText("删除这条日程？").assertExists()
        composeRule.onNodeWithTag("confirm-delete-schedule")
            .performSemanticsAction(SemanticsActions.OnClick)
        composeRule.runOnIdle { assertEquals("event-1", deletedId) }
    }

    private fun draft(id: String?, title: String) = ScheduleEventDraft(
        id = id,
        title = title,
        date = LocalDate.of(2026, 9, 7),
        startsAt = LocalTime.of(8, 0),
        endsAt = LocalTime.of(8, 45),
        location = "",
        note = "",
    )
}
