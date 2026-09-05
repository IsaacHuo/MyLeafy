package com.myleafy.android.features.community

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.myleafy.android.shared.model.PostDto
import com.myleafy.android.ui.theme.MyLeafyTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class CommunityContentTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun filterAndPostClicksDeliverStableValues() {
        var selectedCategory: String? = null
        var openedPost: String? = null
        val post = PostDto(
            id = "post-1",
            author_id = "author-1",
            title = "森林生态学习资料",
            body = "分享本周复习重点",
            category = "学习交流",
        )

        composeRule.setContent {
            MyLeafyTheme(darkTheme = false) {
                CommunityContent(
                    state = CommunityUiState(posts = listOf(post), isInitialLoading = false),
                    onPostClick = { openedPost = it },
                    onComposeClick = {},
                    onSearchClick = {},
                    onNotificationsClick = {},
                    onRefresh = {},
                    onSelectHot = { selectedCategory = "hot" },
                    onSelectLatest = { selectedCategory = it },
                )
            }
        }

        composeRule.onNodeWithTag("community-filter-学习交流").performClick()
        composeRule.runOnIdle { assertEquals("学习交流", selectedCategory) }
        composeRule.onNodeWithTag("community-post-post-1").performClick()
        composeRule.runOnIdle { assertEquals("post-1", openedPost) }
    }

    @Test
    fun refreshFailureKeepsLastSuccessfulPostVisible() {
        composeRule.setContent {
            MyLeafyTheme(darkTheme = false) {
                CommunityContent(
                    state = CommunityUiState(
                        posts = listOf(
                            PostDto(
                                id = "post-1",
                                author_id = "author-1",
                                title = "缓存中的帖子",
                                body = "旧内容仍然可读",
                            ),
                        ),
                        isInitialLoading = false,
                        error = "网络不可达",
                    ),
                    onPostClick = {},
                    onComposeClick = {},
                    onSearchClick = {},
                    onNotificationsClick = {},
                    onRefresh = {},
                    onSelectHot = {},
                    onSelectLatest = {},
                )
            }
        }

        composeRule.onNodeWithText("缓存中的帖子").assertIsDisplayed()
        composeRule.onNodeWithText("刷新失败，已保留上次内容：网络不可达").assertIsDisplayed()
    }
}
