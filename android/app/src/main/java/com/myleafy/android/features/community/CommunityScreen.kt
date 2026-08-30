package com.myleafy.android.features.community

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.shared.model.PostDto
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.leafyPullRefresh
import com.myleafy.android.ui.components.rememberLeafyPullRefreshState

val communityCategories = listOf("学习交流", "校园生活", "活动社团", "问答互助", "闲聊吹水", "二手交易")

@Composable
fun CommunityScreen(
    onPostClick: (String) -> Unit = {},
    onComposeClick: () -> Unit = {},
    onSearchClick: () -> Unit = {},
    onNotificationsClick: () -> Unit = {},
    viewModel: CommunityViewModel = viewModel(
        factory = appViewModelFactory { container ->
            CommunityViewModel(
                repository = container.communityRepository,
                campusId = container.activeAppScopeStore.current.campusId?.rawValue.orEmpty(),
            )
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    LifecycleResumeEffect(Unit) {
        viewModel.refresh()
        viewModel.refreshUnreadCount()
        onPauseOrDispose { }
    }

    CommunityContent(
        state = uiState,
        onPostClick = onPostClick,
        onComposeClick = onComposeClick,
        onSearchClick = onSearchClick,
        onNotificationsClick = onNotificationsClick,
        onRefresh = viewModel::refresh,
        onSelectHot = viewModel::selectHot,
        onSelectLatest = viewModel::selectLatest,
        modifier = modifier,
    )
}

@Composable
fun CommunityContent(
    state: CommunityUiState,
    onPostClick: (String) -> Unit,
    onComposeClick: () -> Unit,
    onSearchClick: () -> Unit,
    onNotificationsClick: () -> Unit,
    onRefresh: () -> Unit,
    onSelectHot: () -> Unit,
    onSelectLatest: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val pullRefreshState = rememberLeafyPullRefreshState(state.isRefreshing, onRefresh)
    Scaffold(
        modifier = modifier,
        topBar = {
            LeafyRootTopBar(
                title = "社区",
                actions = {
                    IconButton(onClick = onSearchClick) {
                        Icon(Icons.Outlined.Search, contentDescription = "搜索社区")
                    }
                    IconButton(onClick = onNotificationsClick) {
                        BadgedBox(
                            badge = {
                                if (state.unreadCount > 0) {
                                    Badge { Text(state.unreadCount.coerceAtMost(99).toString()) }
                                }
                            },
                        ) {
                            Icon(Icons.Outlined.Notifications, contentDescription = "社区通知")
                        }
                    }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = onComposeClick,
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                text = { Text("发帖") },
            )
        },
    ) { contentPadding ->
        when {
            state.isInitialLoading -> Box(
                modifier = Modifier.fillMaxSize().padding(contentPadding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            state.posts.isEmpty() && state.error != null -> Column(
                modifier = Modifier.fillMaxSize().padding(contentPadding).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                LeafyStatusBanner(message = state.error, isError = true)
                Text(
                    text = "网络失败不会展示模拟内容，请检查连接后重试。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(onClick = onRefresh) { Text("重试") }
            }

            else -> LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(contentPadding)
                    .leafyPullRefresh(pullRefreshState, enabled = !state.isRefreshing),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 96.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                item {
                    CommunityFilters(
                        selection = state.selection,
                        onSelectHot = onSelectHot,
                        onSelectLatest = onSelectLatest,
                    )
                }
                if (state.isRefreshing || pullRefreshState.progress > 0f) {
                    item {
                        LinearProgressIndicator(
                            progress = { if (state.isRefreshing) 1f else pullRefreshState.progress },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                state.error?.let { message ->
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            LeafyStatusBanner(message = "刷新失败，已保留上次内容：$message", isError = true)
                            Button(onClick = onRefresh) { Text("重新刷新") }
                        }
                    }
                }
                if (state.posts.isEmpty()) {
                    item {
                        LeafyEmptyState(
                            title = "没有找到内容",
                            message = "换一个分类，或发布第一条校园动态。",
                            icon = Icons.Outlined.Forum,
                            modifier = Modifier.fillMaxWidth().padding(top = 36.dp),
                        )
                    }
                } else {
                    items(state.posts, key = { it.id }) { post ->
                        CommunityPostCard(post, onClick = { onPostClick(post.id) })
                    }
                }
            }
        }
    }
}

@Composable
private fun CommunityFilters(
    selection: CommunityFeedSelection,
    onSelectHot: () -> Unit,
    onSelectLatest: (String?) -> Unit,
) {
    LazyRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(vertical = 4.dp),
    ) {
        item {
            FilterChip(
                selected = selection.mode == CommunityFeedMode.HOT,
                onClick = onSelectHot,
                label = { Text("近七日热门") },
            )
        }
        item {
            FilterChip(
                selected = selection.mode == CommunityFeedMode.LATEST && selection.category == null,
                onClick = { onSelectLatest(null) },
                label = { Text("全部") },
            )
        }
        items(communityCategories) { category ->
            FilterChip(
                selected = selection.mode == CommunityFeedMode.LATEST && selection.category == category,
                onClick = { onSelectLatest(category) },
                label = { Text(category) },
            )
        }
    }
}

@Composable
fun CommunityPostCard(post: PostDto, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Card(modifier = modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = if (post.is_anonymous) "匿名" else post.author?.nickname ?: "北林同学",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f),
                )
                post.category?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(post.title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                post.body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(modifier = Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("${post.like_count} 赞", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("${post.comment_count} 评论", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (post.viewer_has_favorited) {
                    Text("已收藏", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}
