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
    private val scopeKey: String = "",
) : ViewModel() {

    private val _uiState = MutableStateFlow(CommunityUiState())
    val uiState: StateFlow<CommunityUiState> = _uiState.asStateFlow()
    private var loadJob: Job? = null
    private var unreadJob: Job? = null
    private var requestGeneration = 0L
    private var signalJobs = emptyList<Job>()
    private var lastLoadedAt = 0L
    private val cacheEnabled = scopeKey.isNotBlank()

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
        // 先渲染上次成功快照，再决定是否联网；切回 Tab 不再整屏空白。
        val cached = if (cacheEnabled) FeedCache.get(cacheKey(_uiState.value.selection)) else null
        cached?.let {
            _uiState.value = CommunityUiState(
                posts = cached.posts,
                nextCursor = cached.nextCursor,
                selection = cached.selection,
                isInitialLoading = false,
                loadedSelection = cached.selection,
            )
            lastLoadedAt = cached.savedAt
        }
        refreshIfStale()
        refreshUnreadCount()
    }

    fun selectLatest(category: String?) {
        val selection = CommunityFeedSelection(mode = CommunityFeedMode.LATEST, category = category)
        if (_uiState.value.selection == selection) return
        applySelection(selection)
    }

    fun selectHot() {
        val selection = CommunityFeedSelection(mode = CommunityFeedMode.HOT)
        if (_uiState.value.selection == selection) return
        applySelection(selection)
    }

    private fun applySelection(selection: CommunityFeedSelection) {
        val cached = if (cacheEnabled) FeedCache.get(cacheKey(selection)) else null
        _uiState.value = CommunityUiState(
            posts = cached?.posts.orEmpty(),
            nextCursor = cached?.nextCursor,
            selection = selection,
            isInitialLoading = cached == null,
            loadedSelection = cached?.selection,
        )
        lastLoadedAt = cached?.savedAt ?: 0L
        refresh()
    }

    /** 从详情返回或 Tab 重新可见时调用：一分钟内的最新列表不重复请求。 */
    fun refreshIfStale() {
        val current = _uiState.value
        if (current.posts.isNotEmpty() && System.currentTimeMillis() - lastLoadedAt < FRESH_WINDOW_MS) return
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
                val page = repository.feedPage(
                    selection.toQuery(campusId).copy(limit = targetLimit(current, selection)),
                )
                currentCoroutineContext().ensureActive()
                if (generation != requestGeneration) return@launch
                _uiState.value = _uiState.value.copy(
                    posts = page.posts, nextCursor = page.next_cursor, loadedSelection = selection,
                    hasNewPosts = false,
                    isInitialLoading = false, isRefreshing = false, error = null,
                )
                lastLoadedAt = System.currentTimeMillis()
                if (cacheEnabled) {
                    FeedCache.put(
                        cacheKey(selection),
                        CachedFeed(page.posts, page.next_cursor, selection, lastLoadedAt),
                    )
                }
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
                val posts = (snapshot.posts + page.posts).distinctBy { it.id }
                _uiState.value = _uiState.value.copy(posts = posts, nextCursor = page.next_cursor, loadingMore = false)
                if (cacheEnabled) {
                    FeedCache.put(
                        cacheKey(snapshot.selection),
                        CachedFeed(posts, page.next_cursor, snapshot.selection, lastLoadedAt),
                    )
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) {
                if (generation == requestGeneration) {
                    _uiState.value = _uiState.value.copy(
                        loadingMore = false,
                        error = failure.toCommunityMessage("加载更多失败"),
                    )
                }
            }
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

    private fun targetLimit(state: CommunityUiState, selection: CommunityFeedSelection): Int {
        if (state.loadedSelection != selection) return PAGE_SIZE
        return state.posts.size.coerceIn(PAGE_SIZE, MAX_REFRESH_LIMIT)
    }

    private fun cacheKey(selection: CommunityFeedSelection) =
        "$scopeKey|$campusId|${selection.mode}|${selection.category.orEmpty()}"

    private data class CachedFeed(
        val posts: List<PostDto>,
        val nextCursor: String?,
        val selection: CommunityFeedSelection,
        val savedAt: Long,
    )

    /** 进程内 LRU；与 iOS `CommunityFeedCache` 一样只解决 Tab 往返，不做磁盘持久化。 */
    private object FeedCache {
        private const val MAX_ENTRIES = 8
        private val entries = object : LinkedHashMap<String, CachedFeed>(MAX_ENTRIES, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, CachedFeed>?): Boolean =
                size > MAX_ENTRIES
        }

        @Synchronized
        fun get(key: String): CachedFeed? = entries[key]

        @Synchronized
        fun put(key: String, value: CachedFeed) {
            entries[key] = value
        }
    }

    private companion object {
        const val PAGE_SIZE = 20
        const val MAX_REFRESH_LIMIT = 100
        const val FRESH_WINDOW_MS = 60_000L
    }
}
