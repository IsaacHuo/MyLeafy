package com.myleafy.android.features.campus

import android.app.Application
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.testing.LeafyScreenshotTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 平板双栏布局的同步结果提示属于根栏，不能只挂在「学校教学」领域里；
 * 否则在校园生活/自习/体育等入口触发同步后看不到失败或部分失败。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "w700dp-h900dp-xxhdpi", application = Application::class)
class CampusSyncFeedbackTest {
    @get:Rule
    val composeRule = createComposeRule()

    private fun show(state: CampusSyncState) {
        composeRule.setContent {
            LeafyScreenshotTheme {
                CampusDashboard(
                    syncState = state,
                    campusId = CampusID.bjfu,
                    onRetrySync = {},
                    onConsumeSync = {},
                    onGradesClick = {},
                    onExamsClick = {},
                    onClassroomClick = {},
                    onFeatureClick = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        composeRule.waitForIdle()
    }

    @Test
    fun wideLayoutShowsSyncErrorInEveryDomain() {
        show(CampusSyncState.Error("教务登录失败"))
        composeRule.onNodeWithText("教务登录失败").assertIsDisplayed()

        composeRule.onNodeWithTag("campus-domain-Sports").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("教务登录失败").assertIsDisplayed()
    }

    @Test
    fun wideLayoutDoesNotDuplicateSyncWarningInTeaching() {
        show(CampusSyncState.Success(grades = 3, rankings = null, exams = null, warnings = listOf("官方排名：读取超时")))
        composeRule.onNodeWithTag("campus-domain-Teaching").performClick()
        composeRule.waitForIdle()
        composeRule.onAllNodesWithText("官方排名：读取超时", substring = true).assertCountEquals(1)
    }
}
