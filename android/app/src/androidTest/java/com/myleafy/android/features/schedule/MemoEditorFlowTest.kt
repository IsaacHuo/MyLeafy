package com.myleafy.android.features.schedule

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.assertIsDisplayed
import androidx.test.platform.app.InstrumentationRegistry
import android.view.KeyEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.myleafy.android.ui.theme.MyLeafyTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MemoEditorFlowTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun editorAndUnsavedInputSurviveStateRestoration() {
        val restoration = androidx.compose.ui.test.junit4.StateRestorationTester(rule)
        restoration.setContent {
            val draft = androidx.compose.runtime.saveable.rememberSaveable(stateSaver = memoDraftSaver) {
                androidx.compose.runtime.mutableStateOf<MemoDraft?>(MemoDraft())
            }
            MyLeafyTheme {
                draft.value?.let { initial ->
                    MemoEditorSheet(initial, ScheduleMutationState.Error("保存失败，请重试"),
                        onSave = {}, onDelete = null, onConsumeMutation = {},
                        onDismiss = { draft.value = null })
                }
            }
        }
        rule.onNodeWithText("正文").performTextInput("旋转后仍保留的草稿")
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText("旋转后仍保留的草稿").assertIsDisplayed()
        rule.onNodeWithText("保存失败，请重试").assertIsDisplayed()
    }

    @Test
    fun editingBackCanContinueOrDiscardWithoutSaving() {
        var dismissed = false
        var saved: MemoDraft? = null
        rule.setContent {
            MyLeafyTheme {
                MemoEditorSheet(MemoDraft(), ScheduleMutationState.Idle,
                    onSave = { saved = it }, onDelete = null, onConsumeMutation = {},
                    onDismiss = { dismissed = true })
            }
        }
        rule.onNodeWithText("正文").performTextInput("待保存的随记")
        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        rule.waitForIdle()
        // A visible system keyboard consumes the first Back; the sheet receives the next one.
        if (rule.onAllNodesWithText("放弃未保存的更改？").fetchSemanticsNodes().isEmpty()) {
            rule.runOnIdle { assertFalse(dismissed); assertEquals(null, saved) }
            InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        }
        rule.onNodeWithText("放弃未保存的更改？").assertIsDisplayed()
        rule.onNodeWithText("继续编辑").performClick()
        rule.runOnIdle { assertFalse(dismissed); assertEquals(null, saved) }
        rule.onNodeWithText("待保存的随记").assertIsDisplayed()
        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        rule.onNodeWithText("放弃更改").performClick()
        rule.runOnIdle { assertTrue(dismissed); assertEquals(null, saved) }
    }

    @Test
    fun saveRemainsReachableWithKeyboardAndKeepsInput() {
        var saved: MemoDraft? = null
        rule.setContent {
            MyLeafyTheme {
                MemoEditorSheet(MemoDraft(), ScheduleMutationState.Idle,
                    onSave = { saved = it }, onDelete = null, onConsumeMutation = {}, onDismiss = {})
            }
        }
        rule.onNodeWithText("正文").performTextInput("保留输入内容")
        rule.onNodeWithText("保存").performScrollTo().performClick()
        rule.runOnIdle { assertEquals("保留输入内容", saved?.body) }
    }
}
