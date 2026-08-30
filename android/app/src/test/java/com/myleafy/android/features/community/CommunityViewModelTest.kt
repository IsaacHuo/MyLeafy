package com.myleafy.android.features.community

import com.myleafy.android.shared.model.CommentDto
import com.myleafy.android.shared.model.CommentThread
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.NotificationDto
import com.myleafy.android.shared.model.PostDto
import com.myleafy.android.shared.model.ProfileDto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CommunityViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun refreshFailureRetainsLastSuccessfulFeedAndRecovers() = runTest(dispatcher) {
        val repository = FakeCommunityRepository()
        repository.feedResult = Result.success(listOf(samplePost("first")))
        val viewModel = CommunityViewModel(repository, "bjfu")
        testScheduler.advanceUntilIdle()

        assertEquals(listOf("first"), viewModel.uiState.value.posts.map { it.id })
        assertFalse(viewModel.uiState.value.isInitialLoading)

        repository.feedResult = Result.failure(IllegalStateException("offline"))
        viewModel.refresh()
        testScheduler.advanceUntilIdle()

        assertEquals(listOf("first"), viewModel.uiState.value.posts.map { it.id })
        assertTrue(viewModel.uiState.value.error.orEmpty().contains("offline"))

        repository.feedResult = Result.success(listOf(samplePost("second")))
        viewModel.refresh()
        testScheduler.advanceUntilIdle()

        assertEquals(listOf("second"), viewModel.uiState.value.posts.map { it.id })
        assertEquals(null, viewModel.uiState.value.error)
    }

    @Test
    fun selectingHotBuildsSevenDayServerQuery() = runTest(dispatcher) {
        val repository = FakeCommunityRepository()
        val viewModel = CommunityViewModel(repository, "bjfu")
        testScheduler.advanceUntilIdle()

        viewModel.selectHot()
        testScheduler.advanceUntilIdle()

        assertEquals("hot", repository.lastQuery?.mode)
        assertEquals(7, repository.lastQuery?.days)
    }

    private fun samplePost(id: String) = PostDto(id = id, author_id = "author", title = id, body = id)
}

@OptIn(ExperimentalCoroutinesApi::class)
class PostDetailViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun favoriteAndDeleteExposeUpdatedAndCloseStates() = runTest(dispatcher) {
        val repository = FakeCommunityRepository().apply {
            currentPost = PostDto(
                id = "post",
                author_id = "viewer",
                title = "title",
                body = "body",
            )
        }
        val viewModel = PostDetailViewModel(repository, "post")
        testScheduler.advanceUntilIdle()

        viewModel.toggleFavorite()
        testScheduler.advanceUntilIdle()
        assertTrue((viewModel.uiState.value as PostDetailUiState.Loaded).post.viewer_has_favorited)

        viewModel.deletePost()
        testScheduler.advanceUntilIdle()
        assertTrue(repository.deletedPost)
        assertTrue((viewModel.uiState.value as PostDetailUiState.Loaded).shouldClose)
    }

    @Test
    fun commentRetryReusesStableClientAndRequestIds() = runTest(dispatcher) {
        val repository = FakeCommunityRepository().apply {
            currentPost = PostDto(id = "post", author_id = "author", title = "title", body = "body")
            commentFailuresRemaining = 1
        }
        val viewModel = PostDetailViewModel(repository, "post")
        testScheduler.advanceUntilIdle()

        viewModel.createComment("同一条评论")
        testScheduler.advanceUntilIdle()
        viewModel.createComment("同一条评论")
        testScheduler.advanceUntilIdle()

        assertEquals(2, repository.commentRequests.size)
        assertEquals(repository.commentRequests[0], repository.commentRequests[1])
    }
}

private class FakeCommunityRepository : CommunityRepository {
    var feedResult: Result<List<PostDto>> = Result.success(emptyList())
    var lastQuery: FeedQuery? = null
    var currentPost: PostDto? = null
    var deletedPost = false
    var commentFailuresRemaining = 0
    val commentRequests = mutableListOf<Pair<String, String>>()
    override val isAvailable = true
    override val isPlaceholder = false

    override fun feed(query: FeedQuery): Flow<List<PostDto>> = flow {
        lastQuery = query
        emit(feedResult.getOrThrow())
    }

    override suspend fun currentProfile() = ProfileDto(id = "viewer")
    override suspend fun post(postId: String): PostDto? = currentPost
    override suspend fun commentThreads(postId: String, limit: Int): List<CommentThread> = emptyList()
    override suspend fun togglePostLike(postId: String): PostDto = error("unused")
    override suspend fun togglePostFavorite(postId: String): PostDto =
        requireNotNull(currentPost).copy(viewer_has_favorited = !requireNotNull(currentPost).viewer_has_favorited)
    override suspend fun notifications(limit: Int): List<NotificationDto> = emptyList()
    override suspend fun unreadNotificationCount(limit: Int): Int = 0
    override suspend fun markNotificationRead(notificationId: String) = Unit
    override suspend fun markAllNotificationsRead() = Unit
    override suspend fun deletePost(postId: String) { deletedPost = true }
    override suspend fun deleteComment(commentId: String) = Unit
    override suspend fun reportPost(postId: String, reason: String, detail: String?) = Unit
    override suspend fun reportComment(commentId: String, reason: String, detail: String?) = Unit
    override suspend fun blockUser(userId: String, reason: String?) = Unit
    override suspend fun createPost(
        postId: String,
        requestId: String,
        title: String,
        body: String,
        category: String?,
        isAnonymous: Boolean,
    ): PostDto = error("unused")
    override suspend fun createComment(
        commentId: String,
        requestId: String,
        postId: String,
        body: String,
        parentCommentId: String?,
        replyToCommentId: String?,
    ): CommentDto {
        commentRequests += commentId to requestId
        if (commentFailuresRemaining > 0) {
            commentFailuresRemaining--
            error("offline")
        }
        return CommentDto(id = commentId, post_id = postId, author_id = "viewer", body = body)
    }
}
