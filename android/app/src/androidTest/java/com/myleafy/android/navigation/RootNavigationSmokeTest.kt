package com.myleafy.android.navigation

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.printToString
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsProperties
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.myleafy.android.MainActivity
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.network.CampusIdentity
import com.myleafy.android.core.network.SchoolPortal
import com.myleafy.android.core.data.local.stableCourseKey
import org.junit.Before
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RootNavigationSmokeTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun enterLocalMode() {
        composeRule.waitUntil(10_000) {
            composeRule.onAllNodes(androidx.compose.ui.test.hasText("免登录入口")).fetchSemanticsNodes().isNotEmpty() ||
                composeRule.onAllNodes(androidx.compose.ui.test.hasTestTag("root-tab-profile")).fetchSemanticsNodes().isNotEmpty()
        }
        if (composeRule.onAllNodes(androidx.compose.ui.test.hasText("免登录入口")).fetchSemanticsNodes().isNotEmpty()) {
            composeRule.onNodeWithText("免登录入口").performClick()
            composeRule.onNodeWithText("直接进入").performClick()
        }
        try {
            composeRule.waitUntil(10_000) {
                composeRule.onAllNodes(androidx.compose.ui.test.hasTestTag("root-tab-profile")).fetchSemanticsNodes().isNotEmpty()
            }
        } catch (failure: androidx.compose.ui.test.ComposeTimeoutException) {
            throw AssertionError(composeRule.onRoot().printToString(), failure)
        }
    }

    @Test
    fun allRootTabsAreReachableAndSelected() {
        activateCommunityScope()
        RootTab.entries.forEach { tab ->
            composeRule.onNodeWithTag("root-tab-${tab.route}").performClick()
            composeRule.onNodeWithTag("root-tab-${tab.route}").assertIsSelected()
        }
    }

    @Test
    fun navigationMarginsUseThePageBackground() {
        composeRule.onNodeWithTag("root-tab-profile").performClick()
        val pixels = composeRule.onRoot().captureToImage().toPixelMap()
        val page = pixels[pixels.width - 1, pixels.height / 2]
        val bottomMargin = pixels[pixels.width - 1, pixels.height - 1]
        assertEquals(page.red, bottomMargin.red, 0.01f)
        assertEquals(page.green, bottomMargin.green, 0.01f)
        assertEquals(page.blue, bottomMargin.blue, 0.01f)
    }

    @Test
    fun weekPagingReversesAndSurvivesTabSwitch() {
        composeRule.waitUntil(10_000) {
            composeRule.onAllNodes(androidx.compose.ui.test.hasTestTag("timetable-week")).fetchSemanticsNodes().isNotEmpty()
        }
        fun week() = composeRule.onNodeWithTag("timetable-week")
            .fetchSemanticsNode().config[SemanticsProperties.Text].single().text
        val initial = week()
        composeRule.onNodeWithTag("timetable-pager").performTouchInput { swipeLeft() }
        composeRule.waitForIdle()
        assertNotEquals(initial, week())
        composeRule.onNodeWithTag("timetable-pager").performTouchInput { swipeRight() }
        composeRule.waitForIdle()
        assertEquals(initial, week())
        composeRule.onNodeWithTag("timetable-pager").performTouchInput { swipeLeft() }
        composeRule.waitForIdle()
        val selected = week()
        composeRule.onNodeWithTag("root-tab-schedule").performClick()
        composeRule.onNodeWithText("随记", substring = false).performClick()
        composeRule.onNodeWithTag("root-tab-timetable").performClick()
        assertEquals(selected, week())
        composeRule.onNodeWithTag("root-tab-schedule").performClick()
        composeRule.onNodeWithText("随记", substring = false).assertIsSelected()
    }

    @Test
    fun secondaryDestinationHidesBottomBarAndBackRestoresIt() {
        activateCommunityScope()
        composeRule.onNodeWithTag("root-tab-community").performClick()
        composeRule.onNodeWithContentDescription("搜索社区").performClick()

        composeRule.onNodeWithText("搜索社区").assertIsDisplayed()
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
    fun profilePreferencesAndSyncAreRealSecondaryPages() {
        composeRule.onNodeWithTag("root-tab-profile").performClick()
        composeRule.onNodeWithText("个性化").performScrollTo().performClick()
        composeRule.onNodeWithText("跟随系统").assertIsDisplayed()
        composeRule.onNodeWithTag("root-tab-profile").assertDoesNotExist()

        composeRule.runOnUiThread {
            composeRule.activity.onBackPressedDispatcher.onBackPressed()
        }
        composeRule.onNodeWithText("缓存与同步").performScrollTo().performClick()
        composeRule.onNodeWithText("学校数据").assertIsDisplayed()
        composeRule.onNodeWithText("本机数据").assertIsDisplayed()
    }

    @Test
    fun communityTabRemainsVisibleWithoutCapabilityButShowsGuardedState() {
        val application = composeRule.activity.application as MyLeafyApplication
        application.container.activeAppScopeStore.activateGuest()
        composeRule.waitForIdle()

        composeRule.onNodeWithTag("root-tab-community").assertExists().performClick()
        composeRule.onNodeWithText("社区暂不可用").assertIsDisplayed()
        composeRule.onNodeWithText("当前校园入口暂不提供社区服务。").assertIsDisplayed()
    }

    @After
    fun clearActiveScope() {
        val application = composeRule.activity.application as MyLeafyApplication
        application.container.activeAppScopeStore.clear()
    }

    @Test
    fun everyCampusToolOpensAndReturnsToItsOriginalCategory() {
        activateCommunityScope()
        composeRule.onNodeWithTag("root-tab-campus").performClick()
        fun back() {
            composeRule.onNodeWithContentDescription("返回").performClick()
            composeRule.waitForIdle()
        }
        val tools = linkedMapOf(
            "学校教学" to listOf("成绩查询", "考试安排", "教学与培养", "校历与作息", "综素测算", "荣誉记录"),
            "自习安排" to listOf("空闲教室"),
            "体育相关" to listOf("阳光长跑", "体测记录", "场馆开放"),
        )
        for ((category, entries) in tools) {
            composeRule.onNodeWithText(category).performScrollTo().performClick()
            for (title in entries) {
                composeRule.onNodeWithText(title).performScrollTo().performClick()
                composeRule.waitForIdle()
                composeRule.onNodeWithTag("root-tab-campus").assertDoesNotExist()
                back()
                composeRule.onNodeWithText(category).assertIsSelected()
            }
        }
        composeRule.onNodeWithTag("root-tab-timetable").performClick()
        composeRule.onNodeWithTag("root-tab-campus").performClick()
        composeRule.onNodeWithText("体育相关").assertIsSelected()
        composeRule.onNodeWithText("医疗事项").performScrollTo().performClick()
        composeRule.onNodeWithTag("root-tab-campus").assertIsSelected()
        composeRule.onNodeWithText("评价相关").performScrollTo().performClick()
        composeRule.onNodeWithTag("root-tab-campus").assertIsSelected()
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

    @Test fun courseReminderOpensItsWeekAndRejectsAnotherIdentity() {
        val launcherIntent = android.content.Intent(composeRule.activity.intent)
        val container = (composeRule.activity.application as MyLeafyApplication).container
        val scope = container.activeAppScopeStore.current.scopeKey
        val semester = com.myleafy.android.features.timetable.domain.SemesterConfig.currentSemesterId
        val course = com.myleafy.android.core.data.local.CourseEntity(scope, "notification-fixture", semester,
            "通知跳转测试课程", "教师", "", "", "测试教室", 1, listOf(7), listOf(6, 7))
        kotlinx.coroutines.runBlocking { container.courseDao.replaceForSemester(scope, semester, listOf(course)) }
        fun open(identity: String, uri: String) {
            composeRule.runOnUiThread { androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().callActivityOnNewIntent(composeRule.activity, android.content.Intent(composeRule.activity, MainActivity::class.java).setAction(android.content.Intent.ACTION_VIEW)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP or android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .setData(android.net.Uri.parse(uri)).putExtra("courseReminder", true).putExtra("scope", identity)
                .putExtra("semester", semester).putExtra("course", course.stableCourseKey()).putExtra("week", 7)) }
        }
        try {
        open(scope, "myleafy-internal://course/fixture-valid")
        composeRule.waitUntil(5_000) { composeRule.onAllNodesWithText("第 1 / 1 次课 · 第 7 周").fetchSemanticsNodes().isNotEmpty() }
        composeRule.onNodeWithText("第 1 / 1 次课 · 第 7 周").assertIsDisplayed()
        composeRule.onNodeWithText("完成").performClick()
        open("other-identity", "myleafy-internal://course/fixture-invalid")
        composeRule.onNodeWithText("提醒属于其他账号，请切换到对应账号后查看").assertIsDisplayed()
        // ActivityScenario identifies its activity by the original launch intent during teardown.
        } finally { composeRule.runOnUiThread { composeRule.activity.intent = launcherIntent } }
    }

    @Test fun allComprehensiveCollegeRulesRenderWithoutCrashing() {
        activateCommunityScope()
        composeRule.onNodeWithTag("root-tab-campus").performClick()
        composeRule.onNodeWithText("综素测算").performScrollTo().performClick()
        com.myleafy.android.features.campus.ComprehensiveQualityRuleCatalog.participatingCollegeNames.forEach { name ->
            composeRule.onNodeWithTag("comprehensive-colleges").performScrollToNode(hasText(name))
            composeRule.onNodeWithText(name).performClick()
            composeRule.waitForIdle()
            val rule = com.myleafy.android.features.campus.ComprehensiveQualityRuleCatalog.ruleFor(name)
            composeRule.onNodeWithText("规则来源：${rule.status.title}").assertExists()
        }
    }
}
