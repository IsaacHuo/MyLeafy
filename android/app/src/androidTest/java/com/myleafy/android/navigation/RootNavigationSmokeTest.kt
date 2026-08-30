package com.myleafy.android.navigation

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.myleafy.android.MainActivity
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.network.CampusIdentity
import com.myleafy.android.core.network.SchoolPortal
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RootNavigationSmokeTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun allRootTabsAreReachableAndSelected() {
        activateCommunityScope()
        RootTab.entries.forEach { tab ->
            composeRule.onNodeWithTag("root-tab-${tab.route}").performClick()
            composeRule.onNodeWithTag("root-tab-${tab.route}").assertIsSelected()
        }
    }

    @Test
    fun secondaryDestinationHidesBottomBarAndBackRestoresIt() {
        activateCommunityScope()
        composeRule.onNodeWithTag("root-tab-community").performClick()
        composeRule.onNodeWithContentDescription("搜索社区").performClick()

        composeRule.onNodeWithText("界面框架已就绪").assertIsDisplayed()
        composeRule.onNodeWithTag("root-tab-community").assertDoesNotExist()

        composeRule.runOnUiThread {
            composeRule.activity.onBackPressedDispatcher.onBackPressed()
        }
        composeRule.onNodeWithTag("root-tab-community").assertIsSelected()
    }

    @Test
    fun staticHelpPageContainsRealGuidance() {
        composeRule.onNodeWithTag("root-tab-profile").performClick()
        composeRule.onNodeWithText("帮助中心").performClick()

        composeRule.onNodeWithTag("help-content")
            .performScrollToNode(hasText("学校系统与校园网"))
        composeRule.onNodeWithText("学校系统与校园网").assertIsDisplayed()
        composeRule.onNodeWithTag("help-content")
            .performScrollToNode(hasText("数据安全边界"))
        composeRule.onNodeWithText("数据安全边界").assertIsDisplayed()
    }

    @Test
    fun communityTabIsHiddenWithoutCapability() {
        val application = composeRule.activity.application as MyLeafyApplication
        application.container.activeAppScopeStore.clear()
        composeRule.waitForIdle()

        composeRule.onNodeWithTag("root-tab-community").assertDoesNotExist()
    }

    @After
    fun clearActiveScope() {
        val application = composeRule.activity.application as MyLeafyApplication
        application.container.activeAppScopeStore.clear()
    }

    private fun activateCommunityScope() {
        val application = composeRule.activity.application as MyLeafyApplication
        application.container.activeAppScopeStore.activate(
            CampusIdentity(
                campusId = CampusID.bjfu,
                eduId = "android-test-user",
                displayName = null,
                portal = SchoolPortal.UNDERGRADUATE,
                kind = CampusIdentity.IdentityKind.SCHOOL_PORTAL,
            ),
        )
        composeRule.waitForIdle()
    }
}
