package com.myleafy.android.features.community

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.NotificationDto
import com.myleafy.android.shared.model.PostDto
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyErrorState
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

data class CommunitySearchUiState(
    val query: String = "",
    val posts: List<PostDto> = emptyList(),
    val hasSearched: Boolean = false,
    val isLoading: Boolean = false,
    val error: String? = null,
)

class CommunitySearchViewModel(
    private val repository: CommunityRepository,
    private val campusId: String,
) : ViewModel() {
    private val _uiState = MutableStateFlow(CommunitySearchUiState())
    val uiState: StateFlow<CommunitySearchUiState> = _uiState.asStateFlow()

    fun updateQuery(value: String) {
        _uiState.value = _uiState.value.copy(query = value, error = null)
    }

    fun search() {
        val query = _uiState.value.query.trim()
        if (query.isEmpty() || _uiState.value.isLoading) return
        _uiState.value = _uiState.value.copy(isLoading = true, hasSearched = true, error = null)
        viewModelScope.launch {
            runCatching {
                repository.feed(FeedQuery(limit = 30, campus_id = campusId, search = query)).first()
            }.fold(
                onSuccess = { posts -> _uiState.value = _uiState.value.copy(posts = posts, isLoading = false) },
                onFailure = { error ->
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        error = error.toCommunityMessage("搜索失败"),
                    )
                },
            )
        }
    }
}

@Composable
fun CommunitySearchScreen(
    onBack: () -> Unit,
    onPostClick: (String) -> Unit,
    viewModel: CommunitySearchViewModel = viewModel(
        factory = appViewModelFactory { container ->
            CommunitySearchViewModel(
                repository = container.communityRepository,
                campusId = container.activeAppScopeStore.current.campusId?.rawValue.orEmpty(),
            )
        },
    ),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    LeafySecondaryScaffold(title = "搜索社区", onBack = onBack) { contentModifier ->
        Column(modifier = contentModifier.fillMaxSize().padding(horizontal = LeafySpacing.card)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = state.query,
                    onValueChange = viewModel::updateQuery,
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    placeholder = { Text("搜索帖子标题和正文") },
                )
                IconButton(onClick = viewModel::search, enabled = state.query.isNotBlank() && !state.isLoading) {
                    Icon(Icons.Outlined.Search, contentDescription = "搜索")
                }
            }
            Spacer(Modifier.height(LeafySpacing.compact))
            when {
                state.isLoading -> LeafyLoadingState(message = "正在搜索校园动态")
                state.error != null -> LeafyStatusBanner(message = state.error.orEmpty(), isError = true)
                !state.hasSearched -> LeafyEmptyState(
                    title = "查找校园动态",
                    message = "输入课程、活动或校园生活关键词。",
                    icon = Icons.Outlined.Search,
                    modifier = Modifier.fillMaxSize(),
                )
                state.posts.isEmpty() -> LeafyEmptyState(
                    title = "没有搜索结果",
                    message = "换一个关键词再试试。",
                    icon = Icons.Outlined.Search,
                    modifier = Modifier.fillMaxSize(),
                )
                else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
                    items(state.posts, key = { it.id }) { post ->
                        CommunityPostCard(post, onClick = { onPostClick(post.id) })
                    }
                }
            }
        }
    }
}

data class CommunityNotificationsUiState(
    val notifications: List<NotificationDto> = emptyList(),
    val isLoading: Boolean = true,
    val isMutating: Boolean = false,
    val error: String? = null,
)

class CommunityNotificationsViewModel(
    private val repository: CommunityRepository,
) : ViewModel() {
    private val _uiState = MutableStateFlow(CommunityNotificationsUiState())
    val uiState: StateFlow<CommunityNotificationsUiState> = _uiState.asStateFlow()

    init { load() }

    fun load() {
        _uiState.value = _uiState.value.copy(isLoading = true, error = null)
        viewModelScope.launch {
            runCatching { repository.notifications() }.fold(
                onSuccess = { items ->
                    _uiState.value = CommunityNotificationsUiState(notifications = items, isLoading = false)
                },
                onFailure = { error ->
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        error = error.toCommunityMessage("通知加载失败"),
                    )
                },
            )
        }
    }

    fun open(notification: NotificationDto, onReady: (String) -> Unit) {
        val postId = notification.post_id ?: return
        viewModelScope.launch {
            if (!notification.is_read) {
                runCatching { repository.markNotificationRead(notification.id) }
                    .onFailure { error ->
                        _uiState.value = _uiState.value.copy(error = error.toCommunityMessage("标记已读失败"))
                        return@launch
                    }
                _uiState.value = _uiState.value.copy(
                    notifications = _uiState.value.notifications.map {
                        if (it.id == notification.id) it.copy(is_read = true) else it
                    },
                )
            }
            onReady(postId)
        }
    }

    fun markAllRead() {
        if (_uiState.value.isMutating || _uiState.value.notifications.none { !it.is_read }) return
        _uiState.value = _uiState.value.copy(isMutating = true, error = null)
        viewModelScope.launch {
            runCatching { repository.markAllNotificationsRead() }.fold(
                onSuccess = {
                    _uiState.value = _uiState.value.copy(
                        notifications = _uiState.value.notifications.map { it.copy(is_read = true) },
                        isMutating = false,
                    )
                },
                onFailure = { error ->
                    _uiState.value = _uiState.value.copy(
                        isMutating = false,
                        error = error.toCommunityMessage("全部已读失败"),
                    )
                },
            )
        }
    }
}

@Composable
fun CommunityNotificationsScreen(
    onBack: () -> Unit,
    onPostClick: (String) -> Unit,
    viewModel: CommunityNotificationsViewModel = viewModel(
        factory = appViewModelFactory { container ->
            CommunityNotificationsViewModel(container.communityRepository)
        },
    ),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    LifecycleResumeEffect(Unit) {
        viewModel.load()
        onPauseOrDispose { }
    }
    LeafySecondaryScaffold(
        title = "社区通知",
        onBack = onBack,
        actions = {
            TextButton(
                onClick = viewModel::markAllRead,
                enabled = !state.isMutating && state.notifications.any { !it.is_read },
            ) { Text(if (state.isMutating) "处理中" else "全部已读") }
        },
    ) { contentModifier ->
        when {
            state.isLoading -> LeafyLoadingState(
                modifier = contentModifier.fillMaxSize(),
                message = "正在加载社区通知",
            )
            state.notifications.isEmpty() && state.error != null -> LeafyErrorState(
                title = "通知暂时无法加载",
                message = state.error.orEmpty(),
                modifier = contentModifier.fillMaxSize(),
                action = { Button(onClick = viewModel::load) { Text("重试") } },
            )
            state.notifications.isEmpty() -> LeafyEmptyState(
                title = "暂时没有通知",
                message = "评论、点赞等社区互动会出现在这里。",
                icon = Icons.Outlined.NotificationsNone,
                modifier = contentModifier.fillMaxSize(),
            )
            else -> LazyColumn(
                modifier = contentModifier.fillMaxSize().padding(horizontal = LeafySpacing.card),
                verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
            ) {
                state.error?.let { message -> item { LeafyStatusBanner(message = message, isError = true) } }
                items(state.notifications, key = { it.id }) { notification ->
                    NotificationCard(
                        notification = notification,
                        onClick = { viewModel.open(notification, onPostClick) },
                    )
                }
            }
        }
    }
}

@Composable
private fun NotificationCard(notification: NotificationDto, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        enabled = notification.post_id != null,
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.leafySurfaces.content,
        shape = MaterialTheme.shapes.medium,
    ) {
        Row(modifier = Modifier.padding(LeafySpacing.card), verticalAlignment = Alignment.Top) {
            if (!notification.is_read) {
                Text("●", color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(end = LeafySpacing.compact))
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    notification.title.ifBlank { "社区互动" },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = if (notification.is_read) FontWeight.Normal else FontWeight.SemiBold,
                )
                notification.body?.takeIf { it.isNotBlank() }?.let {
                    Spacer(Modifier.height(LeafySpacing.tiny))
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}
