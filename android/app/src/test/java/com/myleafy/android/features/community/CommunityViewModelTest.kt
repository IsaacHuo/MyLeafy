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
import kotlinx.coroutines.flow.first
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

    @Test fun cursorPagingKeepsPinsDeduplicatesAndRetainsCursorOnFailure() = runTest(dispatcher) {
        val repository = FakeCommunityRepository().apply { feedResult = Result.success(listOf(samplePost("pin"), samplePost("first"))); nextCursor = "server-cursor" }
        val model = CommunityViewModel(repository, "bjfu")
        testScheduler.advanceUntilIdle()
        repository.feedResult = Result.failure(IllegalStateException("offline"))
        model.loadMore(); testScheduler.advanceUntilIdle()
        assertEquals("server-cursor", model.uiState.value.nextCursor)
        assertEquals(listOf("pin", "first"), model.uiState.value.posts.map { it.id })
        repository.feedResult = Result.success(listOf(samplePost("pin"), samplePost("second"))); repository.nextCursor = null
        model.loadMore(); testScheduler.advanceUntilIdle()
        assertEquals("server-cursor", repository.lastQuery?.cursor)
        assertEquals(listOf("pin", "first", "second"), model.uiState.value.posts.map { it.id })
        assertEquals(null, model.uiState.value.nextCursor)
        model.selectHot(); testScheduler.advanceUntilIdle()
        assertEquals(null, repository.lastQuery?.cursor)
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

    @Test
    fun selectionChangeClearsOldContentAndCancelledRequestCannotEndNewLoading() = runTest(dispatcher) {
        val repository = FakeCommunityRepository()
        repository.feedResult = Result.success(listOf(samplePost("old")))
        val viewModel = CommunityViewModel(repository, "bjfu")
        testScheduler.advanceUntilIdle()
        val pending = kotlinx.coroutines.CompletableDeferred<List<PostDto>>()
        repository.feedLoader = { pending.await() }
        viewModel.selectLatest("学习交流")
        testScheduler.runCurrent()
        assertTrue(viewModel.uiState.value.posts.isEmpty())
        viewModel.selectHot()
        testScheduler.runCurrent()
        assertTrue(viewModel.uiState.value.isInitialLoading)
        assertEquals(null, viewModel.uiState.value.error)
        pending.complete(listOf(samplePost("hot")))
        testScheduler.advanceUntilIdle()
        assertEquals(CommunityFeedMode.HOT, viewModel.uiState.value.loadedSelection?.mode)
        assertEquals(listOf("hot"), viewModel.uiState.value.posts.map { it.id })
    }

    @Test
    fun lateNonCooperativeResponseCannotReplaceNewSelection() = runTest(dispatcher) {
        val repository = FakeCommunityRepository()
        val oldRequest = kotlinx.coroutines.CompletableDeferred<List<PostDto>>()
        repository.feedLoader = { query ->
            if (query.mode == "hot") listOf(samplePost("new"))
            else kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) { oldRequest.await() }
        }
        val viewModel = CommunityViewModel(repository, "bjfu")
        testScheduler.runCurrent()
        viewModel.selectHot()
        testScheduler.runCurrent()
        oldRequest.complete(listOf(samplePost("stale")))
        testScheduler.advanceUntilIdle()
        assertEquals(listOf("new"), viewModel.uiState.value.posts.map { it.id })
        assertEquals(null, viewModel.uiState.value.error)
    }

    @Test
    fun unreadFailureRetainsLastCount() = runTest(dispatcher) {
        val repository = FakeCommunityRepository().apply { unreadResult = Result.success(7) }
        val viewModel = CommunityViewModel(repository, "bjfu")
        testScheduler.advanceUntilIdle()
        repository.unreadResult = Result.failure(IllegalStateException("offline"))
        viewModel.refreshUnreadCount()
        testScheduler.advanceUntilIdle()
        assertEquals(7, viewModel.uiState.value.unreadCount)
        assertEquals(null, viewModel.uiState.value.error)
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

@OptIn(ExperimentalCoroutinesApi::class)
class ComposePostViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun duplicatePublishIsIgnoredAndFailureKeepsDraftForAnIdempotentRetry() = runTest(dispatcher) {
        val pending = kotlinx.coroutines.CompletableDeferred<PostDto>()
        val repository = FakeCommunityRepository().apply { postCreator = { pending.await() } }
        val viewModel = ComposePostViewModel(repository, android.app.Application())
        viewModel.updateTitle("草稿标题")
        viewModel.updateBody("草稿正文")
        viewModel.submit()
        viewModel.submit()
        testScheduler.runCurrent()
        assertEquals(1, repository.postRequests.size)
        viewModel.updateBody("提交期间不应改变正文")
        pending.completeExceptionally(IllegalStateException("offline"))
        testScheduler.advanceUntilIdle()
        assertFalse(viewModel.uiState.value.published)
        assertEquals("草稿正文", viewModel.uiState.value.body)
        assertTrue(viewModel.uiState.value.errorMessage.orEmpty().contains("offline"))
        repository.postCreator = { PostDto(id = "saved", author_id = "viewer", title = "草稿标题", body = "草稿正文") }
        viewModel.submit()
        testScheduler.advanceUntilIdle()
        assertTrue(viewModel.uiState.value.published)
        assertEquals(repository.postRequests[0], repository.postRequests[1])
        viewModel.submit()
        testScheduler.advanceUntilIdle()
        assertEquals(2, repository.postRequests.size)
    }
}

private class FakeCommunityRepository : CommunityRepository {
    override fun events(scope: String): Flow<Unit> = kotlinx.coroutines.flow.emptyFlow()
    override suspend fun hasAcceptedTerms() = true
    override suspend fun acceptTerms() = Unit
    var nextCursor: String? = null
    override suspend fun feedPage(query: FeedQuery) = com.myleafy.android.shared.model.FeedResponse(posts = feed(query).first(), next_cursor = nextCursor)
    var feedResult: Result<List<PostDto>> = Result.success(emptyList())
    var lastQuery: FeedQuery? = null
    var feedLoader: (suspend (FeedQuery) -> List<PostDto>)? = null
    var unreadResult = Result.success(0)
    var currentPost: PostDto? = null
    var deletedPost = false
    var commentFailuresRemaining = 0
    val commentRequests = mutableListOf<Pair<String, String>>()
    val postRequests = mutableListOf<Pair<String, String>>()
    var postCreator: suspend () -> PostDto = { error("unused") }
    override val isAvailable = true

    override fun feed(query: FeedQuery): Flow<List<PostDto>> = flow {
        lastQuery = query
        emit(feedLoader?.invoke(query) ?: feedResult.getOrThrow())
    }

    override suspend fun currentProfile() = ProfileDto(id = "viewer")
    override fun cacheCurrentProfile(profile: ProfileDto) = Unit
    override fun clearProfileCache() = Unit
    override suspend fun post(postId: String): PostDto? = currentPost
    override suspend fun commentThreads(postId: String, limit: Int): List<CommentThread> = emptyList()
    override suspend fun togglePostLike(postId: String): PostDto = error("unused")
    override suspend fun togglePostFavorite(postId: String): PostDto =
        requireNotNull(currentPost).copy(viewer_has_favorited = !requireNotNull(currentPost).viewer_has_favorited)
    override suspend fun notifications(limit: Int): List<NotificationDto> = emptyList()
    override suspend fun unreadNotificationCount(limit: Int): Int = unreadResult.getOrThrow()
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
        images: List<CommunityPostImageUpload>,
    ): PostDto {
        postRequests += postId to requestId
        return postCreator()
    }
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
