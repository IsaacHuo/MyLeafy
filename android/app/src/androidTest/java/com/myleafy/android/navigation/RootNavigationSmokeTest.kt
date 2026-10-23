package com.myleafy.android.navigation

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.assertTextContains
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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

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
    fun timetablePhotoCoversTheShellAndRestoresAfterTabsAndSettings() {
        val store = (composeRule.activity.application as MyLeafyApplication).container.settingsStore
        val original = runBlocking { store.settings.first().timetableBackground }
        val photo = java.io.File(composeRule.activity.cacheDir, "navigation-backdrop.png")
        val bitmap = android.graphics.Bitmap.createBitmap(40, 80, android.graphics.Bitmap.Config.ARGB_8888)
        android.graphics.Canvas(bitmap).apply {
            drawColor(android.graphics.Color.rgb(225, 237, 217))
            drawCircle(15f, 45f, 28f, android.graphics.Paint().apply { color = android.graphics.Color.rgb(83, 139, 108) })
        }
        photo.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        val background = com.myleafy.android.core.prefs.TimetableBackgroundSettings(enabled = true, kind = "photo", photoPath = photo.absolutePath)
        fun waitForPhoto() = composeRule.waitUntil(10_000) {
            composeRule.onAllNodes(androidx.compose.ui.test.hasTestTag("timetable-photo")).fetchSemanticsNodes().size == 1
        }
        try {
            composeRule.onNodeWithTag("root-tab-timetable").performClick()
            runBlocking { store.setTimetableBackground(background) }
            waitForPhoto()
            assertEquals(composeRule.onRoot().fetchSemanticsNode().boundsInRoot,
                composeRule.onNodeWithTag("timetable-photo").fetchSemanticsNode().boundsInRoot)
            composeRule.onNodeWithTag("timetable-axis-period-13", useUnmergedTree = true).assertIsDisplayed()
            com.myleafy.android.testing.captureRenderReview("timetable-full-backdrop")
            if (androidx.test.platform.app.InstrumentationRegistry.getArguments().getString("recordReview") == "true") {
                val screen = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
                java.io.File(composeRule.activity.getExternalFilesDir(null), "timetable-full-backdrop.png").outputStream().use {
                    check(screen.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it))
                }
                screen.recycle()
            }
            listOf("campus", "profile").forEach { route ->
                composeRule.onNodeWithTag("root-tab-$route").performClick()
                composeRule.onNodeWithTag("timetable-photo").assertDoesNotExist()
                composeRule.onNodeWithTag("root-tab-timetable").performClick()
                waitForPhoto()
            }
            // 日迹是校园二级页面，仍然不能覆盖课表照片背景。
            composeRule.onNodeWithTag("root-tab-campus").performClick()
            composeRule.onNodeWithText("日迹记录").performClick()
            composeRule.onNodeWithTag("timetable-photo").assertDoesNotExist()
            composeRule.runOnUiThread { composeRule.activity.onBackPressedDispatcher.onBackPressed() }
            composeRule.onNodeWithTag("root-tab-timetable").performClick()
            waitForPhoto()
            composeRule.onNodeWithTag("root-tab-profile").performClick()
            composeRule.onNodeWithText("课表背景").performScrollTo().performClick()
            composeRule.onNodeWithTag("timetable-photo").assertDoesNotExist()
            composeRule.onNodeWithTag("root-tab-profile").assertDoesNotExist()
            composeRule.runOnUiThread { composeRule.activity.onBackPressedDispatcher.onBackPressed() }
            composeRule.onNodeWithTag("root-tab-timetable").performClick()
            waitForPhoto()
            runBlocking { store.setTimetableBackground(background.copy(enabled = false)) }
            composeRule.waitUntil(10_000) {
                composeRule.onAllNodes(androidx.compose.ui.test.hasTestTag("timetable-background")).fetchSemanticsNodes().isEmpty()
            }
            runBlocking { store.setTimetableBackground(background.copy(kind = "color", colorHex = "#A3C1B0")) }
            composeRule.waitUntil(10_000) {
                composeRule.onAllNodes(androidx.compose.ui.test.hasTestTag("timetable-background")).fetchSemanticsNodes().size == 1
            }
            composeRule.onNodeWithTag("timetable-photo").assertDoesNotExist()
        } finally {
            runBlocking { store.setTimetableBackground(original) }
            photo.delete()
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
        // 根页面现在有一层很淡的主题渐变，纵向两端允许极小亮度差；
        // 真正要守住的是“系统栏留白不是黑窗”，而不是逐通道完全相等。
        fun luminance(color: androidx.compose.ui.graphics.Color) =
            color.red * 0.299f + color.green * 0.587f + color.blue * 0.114f
        assertEquals(luminance(page), luminance(bottomMargin), 0.06f)
        org.junit.Assert.assertTrue(luminance(bottomMargin) > 0.5f)
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
        composeRule.onNodeWithTag("root-tab-campus").performClick()
        composeRule.onNodeWithTag("root-tab-timetable").performClick()
        assertEquals(selected, week())
    }

    @Test
    fun secondaryDestinationHidesBottomBarAndBackRestoresIt() {
        activateCommunityScope()
        composeRule.onNodeWithTag("root-tab-campus").performClick()
        composeRule.onNodeWithTag("campus-life-community").performClick()
        composeRule.onNodeWithContentDescription("搜索社区").performClick()

        composeRule.onNodeWithText("搜索社区").assertIsDisplayed()
        composeRule.onNodeWithTag("root-tab-campus").assertDoesNotExist()

        composeRule.runOnUiThread {
            composeRule.activity.onBackPressedDispatcher.onBackPressed()
        }
        composeRule.onNodeWithTag("root-tab-campus").assertDoesNotExist()
        composeRule.runOnUiThread {
            composeRule.activity.onBackPressedDispatcher.onBackPressed()
        }
        composeRule.onNodeWithTag("root-tab-campus").assertIsSelected()
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
    fun campusLifeHidesCommunityEntryWithoutCapability() {
        val application = composeRule.activity.application as MyLeafyApplication
        application.container.activeAppScopeStore.activateGuest()
        composeRule.waitForIdle()

        composeRule.onNodeWithTag("root-tab-campus").performClick()
        composeRule.onNodeWithTag("campus-life-schedule").assertExists()
        composeRule.onNodeWithTag("campus-life-community").assertDoesNotExist()
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
            "Teaching" to listOf("成绩查询", "考试安排", "教学与培养", "校历与作息", "综素测算", "荣誉记录"),
            "SelfStudy" to listOf("空闲教室"),
            "Sports" to listOf("阳光长跑", "体测记录", "场馆开放"),
        )
        for ((domain, entries) in tools) {
            selectCampusDomain(domain)
            for (title in entries) {
                composeRule.onNodeWithText(title).performScrollTo().performClick()
                composeRule.waitForIdle()
                composeRule.onNodeWithTag("root-tab-campus").assertDoesNotExist()
                back()
                selectCampusDomain(domain)
                composeRule.onNodeWithTag("campus-domain-$domain").assertIsSelected()
            }
        }
        composeRule.onNodeWithTag("root-tab-timetable").performClick()
        composeRule.onNodeWithTag("root-tab-campus").performClick()
        // Sports 是最后一个可见的窄屏胶囊；先恢复它再滚动到医疗/评价领域。
        selectCampusDomain("Sports")
        composeRule.onNodeWithTag("campus-domain-Sports").assertIsSelected()
        selectCampusDomain("Medical")
        composeRule.onNodeWithTag("root-tab-campus").assertIsSelected()
        selectCampusDomain("Ratings")
        composeRule.onNodeWithTag("root-tab-campus").assertIsSelected()
    }

    /** 校园领域在窄屏是横向 LazyRow、宽屏是竖向栏；先滚动到目标再点击。 */
    private fun selectCampusDomain(domain: String) {
        val tag = "campus-domain-$domain"
        val chips = composeRule.onAllNodesWithTag("campus-domain-chips").fetchSemanticsNodes()
        if (chips.isNotEmpty()) {
            composeRule.onNodeWithTag("campus-domain-chips").performScrollToNode(hasTestTag(tag))
        } else {
            composeRule.onNodeWithTag("campus-domain-sidebar").performScrollToNode(hasTestTag(tag))
        }
        composeRule.onNodeWithTag(tag).performClick()
        composeRule.waitForIdle()
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
            composeRule.onNodeWithText("作业、考试、分组或老师要求").performTextInput("竖屏课程备注草稿")
            val automation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
            composeRule.onNodeWithText("作业、考试、分组或老师要求").assertTextContains("竖屏课程备注草稿")
            android.os.ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand("input keyevent 4")).use { it.readBytes() }
            composeRule.onNodeWithText("完成").performScrollTo().performClick()
            composeRule.waitUntil(5_000) { composeRule.onAllNodesWithText("放弃更改").fetchSemanticsNodes().isNotEmpty() }
            composeRule.onNodeWithText("放弃更改").performClick()
            open("other-identity", "myleafy-internal://course/fixture-invalid")
            composeRule.onNodeWithText("提醒属于其他账号，请切换到对应账号后查看").assertIsDisplayed()
            // ActivityScenario identifies its activity by the original launch intent during teardown.
        } finally {
            composeRule.runOnUiThread { composeRule.activity.intent = launcherIntent }
        }
    }

    @Test fun allComprehensiveCollegeRulesRenderWithoutCrashing() {
        activateCommunityScope()
        composeRule.onNodeWithTag("root-tab-campus").performClick()
        selectCampusDomain("Teaching")
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
