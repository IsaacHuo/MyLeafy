package com.myleafy.android.features.community

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.PostDto
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.util.logging.Logger
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

enum class CommunityFeedMode { LATEST, HOT }

data class CommunityFeedSelection(
    val mode: CommunityFeedMode = CommunityFeedMode.LATEST,
    val category: String? = null,
) {
    fun toQuery(campusId: String, search: String? = null): FeedQuery = FeedQuery(
        limit = 20,
        campus_id = campusId,
        mode = if (mode == CommunityFeedMode.HOT) "hot" else null,
        days = if (mode == CommunityFeedMode.HOT) 7 else null,
        // Cloudflare feed 的 hot 模式 不接受分类或搜索，切换热门时必须清空二者。
        category = category.takeIf { mode == CommunityFeedMode.LATEST },
        search = search?.trim()?.takeIf { it.isNotEmpty() && mode == CommunityFeedMode.LATEST },
    )
}

data class CommunityUiState(
    val posts: List<PostDto> = emptyList(),
    val nextCursor: String? = null,
    val loadingMore: Boolean = false,
    val selection: CommunityFeedSelection = CommunityFeedSelection(),
    val isInitialLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val unreadCount: Int = 0,
    val hasNewPosts: Boolean = false,
    val loadedSelection: CommunityFeedSelection? = null,
)

/** 社区 Feed 状态持有者；刷新失败时保留最近一次成功列表。 */
class CommunityViewModel(
    private val repository: CommunityRepository,
    private val campusId: String,
) : ViewModel() {

    private val _uiState = MutableStateFlow(CommunityUiState())
    val uiState: StateFlow<CommunityUiState> = _uiState.asStateFlow()
    private var loadJob: Job? = null
    private var unreadJob: Job? = null
    private var requestGeneration = 0L
    private var signalJobs = emptyList<Job>()
    fun startSignals() {
        if (signalJobs.any { it.isActive }) return
        signalJobs = listOf("feed", "notifications").map { kind ->
            viewModelScope.launch {
                var retries = 0
                while (true) {
                    try {
                        repository.events(kind).collect {
                            if (kind == "feed") _uiState.value = _uiState.value.copy(hasNewPosts = true)
                            else refreshUnreadCount()
                            retries = 0
                        }
                        break
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (failure: Exception) {
                        Logger.getLogger("CommunityViewModel").warning("$kind subscription interrupted: ${failure.javaClass.simpleName}")
                        kotlinx.coroutines.delay((1_000L shl retries.coerceAtMost(5)).coerceAtMost(30_000L))
                        retries++
                    }
                }
            }
        }
    }
    fun stopSignals() { signalJobs.forEach(Job::cancel); signalJobs = emptyList() }


    init {
        refresh()
    }

    fun selectLatest(category: String?) {
        val selection = CommunityFeedSelection(mode = CommunityFeedMode.LATEST, category = category)
        if (_uiState.value.selection == selection) return
        _uiState.value = _uiState.value.copy(selection = selection, posts = emptyList(), nextCursor = null, loadingMore = false, loadedSelection = null, error = null)
        refresh()
    }

    fun selectHot() {
        val selection = CommunityFeedSelection(mode = CommunityFeedMode.HOT)
        if (_uiState.value.selection == selection) return
        _uiState.value = _uiState.value.copy(selection = selection, posts = emptyList(), nextCursor = null, loadingMore = false, loadedSelection = null, error = null)
        refresh()
    }

    fun refresh() {
        val generation = ++requestGeneration
        loadJob?.cancel()
        val current = _uiState.value
        val selection = current.selection
        _uiState.value = current.copy(
            isInitialLoading = current.posts.isEmpty(),
            isRefreshing = current.posts.isNotEmpty(),
            error = null, loadingMore = false,
        )
        loadJob = viewModelScope.launch {
            try {
                val page = repository.feedPage(selection.toQuery(campusId))
                currentCoroutineContext().ensureActive()
                if (generation != requestGeneration) return@launch
                _uiState.value = _uiState.value.copy(
                    posts = page.posts, nextCursor = page.next_cursor, loadedSelection = selection, hasNewPosts = false,
                    isInitialLoading = false, isRefreshing = false, error = null,
                )
                refreshUnreadCount()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (generation == requestGeneration) {
                    _uiState.value = _uiState.value.copy(
                        isInitialLoading = false, isRefreshing = false,
                        error = error.toCommunityMessage("社区加载失败"),
                    )
                }
            }
        }
    }

    fun loadMore() {
        val snapshot = _uiState.value
        val cursor = snapshot.nextCursor ?: return
        if (snapshot.loadingMore || snapshot.isRefreshing || snapshot.isInitialLoading || snapshot.selection != snapshot.loadedSelection) return
        val generation = ++requestGeneration
        loadJob?.cancel()
        _uiState.value = snapshot.copy(loadingMore = true, error = null)
        loadJob = viewModelScope.launch {
            try {
                val page = repository.feedPage(snapshot.selection.toQuery(campusId).copy(cursor = cursor))
                currentCoroutineContext().ensureActive()
                if (generation != requestGeneration) return@launch
                _uiState.value = _uiState.value.copy(posts = (snapshot.posts + page.posts).distinctBy { it.id }, nextCursor = page.next_cursor, loadingMore = false)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { if (generation == requestGeneration) _uiState.value = _uiState.value.copy(loadingMore = false, error = failure.toCommunityMessage("加载更多失败")) }
        }
    }

    fun refreshUnreadCount() {
        if (unreadJob?.isActive == true) return
        unreadJob = viewModelScope.launch {
            try {
                val count = repository.unreadNotificationCount()
                currentCoroutineContext().ensureActive()
                _uiState.value = _uiState.value.copy(unreadCount = count)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Logger.getLogger("CommunityViewModel").warning("Unread refresh failed: ${error.javaClass.simpleName}")
            }
        }
    }
}
