package com.myleafy.android.testing

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
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
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafyDestructiveButton
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyErrorState
import com.myleafy.android.ui.components.LeafyFeatureCard
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryButton
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafySettingsDivider
import com.myleafy.android.ui.components.LeafySettingsGroup
import com.myleafy.android.ui.components.LeafySettingsRow
import com.myleafy.android.ui.components.LeafySnackbarHost
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyToolRow
import com.myleafy.android.ui.theme.LeafySpacing
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Design-system goldens. The first four keep their original sampler content so the
 * before/after diff stays a pure visual diff; the extra samplers cover the states
 * that used to be missing (long error, loading, empty, surface, snackbar) and the
 * bottom half of the 200% font page.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class LeafyDesignSystemScreenshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun componentsLight() = captureSampler(darkTheme = false, fontScale = 1f)

    @Test
    fun componentsDark() = captureSampler(darkTheme = true, fontScale = 1f)

    @Test
    fun componentsFontScale130() = captureSampler(darkTheme = false, fontScale = 1.3f)

    /**
     * 200% font: the primary action must stay a working hit target at the top of
     * the page, not only look right in the screenshot.
     */
    @Test
    fun componentsFontScale200() {
        var primaryClicks = 0
        renderSampler(
            darkTheme = false,
            fontScale = 2f,
            onPrimaryClick = { primaryClicks += 1 },
        )
        composeRule.onNodeWithText("主要操作").assertIsDisplayed().performClick()
        composeRule.runOnIdle { assertTrue(primaryClicks == 1) }
        capture()
    }

    /**
     * The companion to the test above: the parts that sit below the fold at 200%
     * font must still be reachable by scrolling, with their text unclipped.
     */
    @Test
    fun componentsFontScale200BottomReachability() {
        renderSampler(darkTheme = false, fontScale = 2f)
        composeRule.onNode(hasScrollAction()).performScrollToNode(hasText("还没有日程"))
        composeRule.onNodeWithText("还没有日程").assertIsDisplayed()
        composeRule
            .onNodeWithText("添加第一项个人日程后，会在这里显示。", useUnmergedTree = true)
            .assertTextLayoutFits()
        composeRule
            .onNodeWithText("上课前 30 分钟通知", useUnmergedTree = true)
            .assertTextLayoutFits()
        capture()
    }

    @Test
    fun extendedComponentsLight() = captureExtended(darkTheme = false)

    @Test
    fun extendedComponentsDark() = captureExtended(darkTheme = true)

    /** Long refresh/validation copy at 130% font must wrap instead of clipping. */
    @Test
    fun longMessagesFontScale130() {
        composeRule.setContent {
            LeafyScreenshotTheme(fontScale = 1.3f) {
                Column(
                    modifier = Modifier
                        .verticalScroll(rememberScrollState())
                        .padding(LeafySpacing.page),
                    verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
                ) {
                    LeafyStatusBanner(message = ScreenshotData.LONG_ERROR_MESSAGE, isError = true)
                    LeafyErrorState(
                        title = "校园数据暂不可用",
                        message = ScreenshotData.LONG_ERROR_MESSAGE,
                        action = { LeafyPrimaryButton(onClick = {}) { Text("重试") } },
                    )
                    LeafyEmptyState(
                        title = "本学期还没有课程",
                        message = ScreenshotData.LONG_EMPTY_MESSAGE,
                        icon = Icons.Outlined.CalendarMonth,
                    )
                }
            }
        }
        composeRule.waitForIdle()
        composeRule
            .onNodeWithText(ScreenshotData.LONG_ERROR_MESSAGE, useUnmergedTree = true)
            .assertTextLayoutFits()
        composeRule
            .onNodeWithText(ScreenshotData.LONG_EMPTY_MESSAGE, useUnmergedTree = true)
            .assertTextLayoutFits()
        capture()
    }

    @Test
    fun snackbarLongMessageLight() {
        composeRule.setContent {
            LeafyScreenshotTheme {
                val hostState = remember { SnackbarHostState() }
                LaunchedEffect(Unit) {
                    hostState.showSnackbar(
                        message = ScreenshotData.LONG_SNACKBAR_MESSAGE,
                        actionLabel = "设置",
                        duration = SnackbarDuration.Indefinite,
                    )
                }
                Box(modifier = Modifier.fillMaxSize()) {
                    LeafySnackbarHost(
                        hostState = hostState,
                        modifier = Modifier.align(Alignment.BottomCenter),
                    )
                }
            }
        }
        composeRule.waitForIdle()
        composeRule
            .onNodeWithText(ScreenshotData.LONG_SNACKBAR_MESSAGE, useUnmergedTree = true)
            .assertTextLayoutFits()
        composeRule.onNodeWithText("设置").assertIsDisplayed()
        capture()
    }

    private fun captureSampler(darkTheme: Boolean, fontScale: Float) {
        renderSampler(darkTheme = darkTheme, fontScale = fontScale)
        capture()
    }

    private fun renderSampler(
        darkTheme: Boolean,
        fontScale: Float,
        onPrimaryClick: () -> Unit = {},
    ) {
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = darkTheme, fontScale = fontScale) {
                Column(
                    modifier = Modifier
                        .verticalScroll(rememberScrollState())
                        .padding(LeafySpacing.page),
                    verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
                ) {
                    Text("MyLeafy Design System", style = MaterialTheme.typography.headlineSmall)
                    LeafyPrimaryButton(onClick = onPrimaryClick, modifier = Modifier.fillMaxWidth()) {
                        Text("主要操作")
                    }
                    LeafySecondaryButton(onClick = {}, modifier = Modifier.fillMaxWidth()) {
                        Text("次要操作")
                    }
                    LeafyStatusBanner(message = "课程数据已同步", isError = false)
                    LeafyStatusBanner(message = "刷新失败，已保留上次内容", isError = true)
                    LeafySettingsGroup(title = "设置分组") {
                        LeafySettingsRow(
                            headlineContent = { Text("课程提醒") },
                            supportingContent = { Text("上课前 30 分钟通知") },
                        )
                        LeafySettingsDivider()
                        LeafySettingsRow(headlineContent = { Text("深色模式") })
                    }
                    LeafyEmptyState(
                        title = "还没有日程",
                        message = "添加第一项个人日程后，会在这里显示。",
                        icon = Icons.Outlined.CalendarMonth,
                    )
                }
            }
        }
        composeRule.waitForIdle()
    }

    private fun captureExtended(darkTheme: Boolean) {
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = darkTheme) {
                Column(
                    modifier = Modifier
                        .verticalScroll(rememberScrollState())
                        .padding(LeafySpacing.page),
                    verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
                ) {
                    LeafySectionHeader(
                        title = "组件扩展",
                        supportingText = "表面、工具行、加载与错误状态",
                    )
                    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(LeafySpacing.page)) {
                            Text("内容表面", style = MaterialTheme.typography.titleMedium)
                            Text(
                                "普通内容默认平面呈现，只有分组与浮层使用表面。",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    LeafyToolRow(
                        headlineContent = { Text("工具行") },
                        supportingContent = { Text("标题、说明与尾部跳转同排") },
                        leadingContent = { Icon(Icons.Outlined.CloudSync, contentDescription = null) },
                        trailingContent = {
                            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null)
                        },
                        onClick = {},
                    )
                    LeafyFeatureCard(
                        title = "成绩与排名",
                        description = "成绩明细、官方 GPA 与班级/专业排名",
                        icon = Icons.Outlined.Info,
                        onClick = {},
                    )
                    LeafyLoadingState(message = "正在加载校园动态")
                    LeafyErrorState(
                        title = "社区暂时无法加载",
                        message = "网络失败不会展示模拟内容，请检查连接后重试。",
                        action = { LeafyPrimaryButton(onClick = {}) { Text("重试") } },
                    )
                    LeafyEmptyState(
                        title = "还没有随记",
                        message = "随记只保存在当前 Android 身份作用域。",
                        icon = Icons.Outlined.CalendarMonth,
                    )
                    LeafyDestructiveButton(
                        onClick = {},
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("退出登录") }
                }
            }
        }
        composeRule.waitForIdle()
        capture()
    }

    private fun capture() = composeRule.onRoot().captureRoboImage()
}
