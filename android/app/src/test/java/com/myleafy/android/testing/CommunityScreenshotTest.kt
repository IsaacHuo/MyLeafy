package com.myleafy.android.testing

import android.app.Application
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.community.CommunityContent
import com.myleafy.android.features.community.CommunityUiState
import com.myleafy.android.shared.model.PostDto
import com.myleafy.android.shared.model.ProfileDto
import com.myleafy.android.ui.theme.MyLeafyTheme
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class CommunityScreenshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test fun contentLight() {
        composeRule.setContent {
            MyLeafyTheme {
                CommunityContent(
                    state = CommunityUiState(
                        isInitialLoading = false,
                        unreadCount = 3,
                        posts = listOf(
                            post("1", "本周图书馆延长开放时间", "学习交流", 18, 6),
                            post("2", "寻找周末一起打羽毛球的同学", "活动社团", 9, 12),
                        ),
                    ),
                    onPostClick = {}, onComposeClick = {}, onSearchClick = {},
                    onNotificationsClick = {}, onRefresh = {}, onSelectHot = {}, onSelectLatest = {},
                )
            }
        }
        composeRule.waitForIdle()
        composeRule.onRoot().captureRoboImage()
    }

    private fun post(id: String, title: String, category: String, likes: Int, comments: Int) = PostDto(
        id = id,
        author_id = "author-$id",
        title = title,
        body = "固定测试内容用于验证作者、时间、分类、正文与互动数据的视觉节奏。",
        category = category,
        created_at = "2026-09-04T08:30:00+08:00",
        like_count = likes,
        comment_count = comments,
        author = ProfileDto(id = "author-$id", nickname = "北林同学"),
    )
}
