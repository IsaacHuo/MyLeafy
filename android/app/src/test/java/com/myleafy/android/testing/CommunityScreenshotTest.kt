package com.myleafy.android.testing

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.community.CommunityContent
import com.myleafy.android.features.community.CommunityUiState
import com.myleafy.android.shared.model.PostDto
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
 * Community feed goldens: flat information flow, filter row, long-text rhythm and
 * refresh failure that keeps the last successful list.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class CommunityScreenshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun contentLight() {
        render(state = defaultState())
        capture()
    }

    @Test
    fun contentDark() {
        render(state = defaultState(), darkTheme = true)
        capture()
    }

    @Test
    @Config(sdk = [36], qualifiers = "w840dp-h900dp-xxhdpi", application = Application::class)
    fun contentWide840() {
        render(state = defaultState())
        capture()
    }

    /** Refresh failure keeps the previous list and shows the long error inline. */
    @Test
    fun refreshFailureKeepsContentWithLongError() {
        render(
            state = defaultState().copy(error = ScreenshotData.LONG_ERROR_MESSAGE),
        )
        composeRule
            .onNodeWithText(ScreenshotData.LONG_ERROR_MESSAGE, substring = true, useUnmergedTree = true)
            .assertTextLayoutFits()
        composeRule.onNodeWithText("重新刷新").assertIsDisplayed().performClick()
        composeRule.runOnIdle { assertTrue(refreshClicks == 1) }
        capture()
    }

    /**
     * 200% font scale: the feed, the filter row and the compose action all stay
     * reachable and clickable, and post metadata is not clipped.
     */
    @Test
    fun contentFontScale200Reachability() {
        var selectedPostId: String? = null
        render(
            state = loadedState(
                postFixture(
                    id = "1",
                    title = ScreenshotData.LONG_POST_TITLE,
                    category = "学习交流",
                    body = ScreenshotData.LONG_EMPTY_MESSAGE,
                    likes = 18,
                    comments = 6,
                ),
                postFixture(id = "2", title = "寻找周末一起打羽毛球的同学", category = "活动社团", likes = 9, comments = 12),
            ),
            fontScale = 2f,
            onPostClick = { selectedPostId = it },
        )

        composeRule.onNodeWithText("发帖").assertIsDisplayed().performClick()
        composeRule.runOnIdle { assertTrue(composeClicks == 1) }

        composeRule.onNodeWithTag("community-post-1").performClick()
        composeRule.runOnIdle { assertEquals("1", selectedPostId) }

        composeRule
            .scrollableContaining("community-post-1")
            .performScrollToNode(hasTestTag("community-post-2"))
        composeRule.onNodeWithTag("community-post-2").assertIsDisplayed().performClick()
        composeRule.runOnIdle { assertEquals("2", selectedPostId) }

        composeRule
            .onNodeWithText("18 赞", useUnmergedTree = true)
            .assertTextLayoutFits()
        capture()
    }

    private var refreshClicks = 0
    private var composeClicks = 0

    private fun loadedState(vararg posts: PostDto) = CommunityUiState(
        isInitialLoading = false,
        unreadCount = 3,
        posts = posts.toList(),
    )

    private fun defaultState() = loadedState(
        postFixture("1", "本周图书馆延长开放时间", "学习交流", likes = 18, comments = 6),
        postFixture("2", "寻找周末一起打羽毛球的同学", "活动社团", likes = 9, comments = 12),
    )

    private fun render(
        state: CommunityUiState,
        darkTheme: Boolean = false,
        fontScale: Float = 1f,
        onPostClick: (String) -> Unit = {},
    ) {
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = darkTheme, fontScale = fontScale) {
                CommunityContent(
                    state = state,
                    onPostClick = onPostClick,
                    onComposeClick = { composeClicks += 1 },
                    onSearchClick = {},
                    onNotificationsClick = {},
                    onRefresh = { refreshClicks += 1 },
                    onSelectHot = {},
                    onSelectLatest = {},
                )
            }
        }
        composeRule.waitForIdle()
    }

    private fun capture() = composeRule.onRoot().captureRoboImage()
}
