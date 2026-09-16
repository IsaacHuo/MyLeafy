package com.myleafy.android.features.community

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.shared.model.PostDto
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyErrorState
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.leafyPullRefresh
import com.myleafy.android.ui.components.rememberLeafyPullRefreshState
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces

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
        containerColor = MaterialTheme.leafySurfaces.page,
        topBar = {
            LeafyRootTopBar(
                title = "社区",
                actions = {
                    LeafyActionIconButton(onClick = onSearchClick) {
                        Icon(Icons.Outlined.Search, contentDescription = "搜索社区")
                    }
                    LeafyActionIconButton(onClick = onNotificationsClick) {
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
            state.isInitialLoading -> LeafyLoadingState(
                modifier = Modifier.fillMaxSize().padding(contentPadding),
                message = "正在加载校园动态",
            )

            state.posts.isEmpty() && state.error != null -> LeafyErrorState(
                title = "社区暂时无法加载",
                message = "${state.error}\n网络失败不会展示模拟内容，请检查连接后重试。",
                modifier = Modifier.fillMaxSize().padding(contentPadding),
                action = { LeafyPrimaryButton(onClick = onRefresh) { Text("重试") } },
            )

            else -> LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(contentPadding)
                    .leafyPullRefresh(pullRefreshState, enabled = !state.isRefreshing),
                contentPadding = PaddingValues(
                    start = LeafySpacing.card,
                    end = LeafySpacing.card,
                    bottom = LeafyComponentSize.floatingActionClearance,
                ),
                verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
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
                        Column(verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                            LeafyStatusBanner(message = "刷新失败，已保留上次内容：$message", isError = true)
                            LeafyPrimaryButton(onClick = onRefresh) { Text("重新刷新") }
                        }
                    }
                }
                if (state.posts.isEmpty()) {
                    item {
                        LeafyEmptyState(
                            title = "没有找到内容",
                            message = "换一个分类，或发布第一条校园动态。",
                            icon = Icons.Outlined.Forum,
                            modifier = Modifier.fillMaxWidth().padding(top = LeafySpacing.spacious),
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
        horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
        contentPadding = PaddingValues(vertical = LeafySpacing.tiny),
    ) {
        item {
            CommunityFilterChip(
                label = "近七日热门",
                selected = selection.mode == CommunityFeedMode.HOT,
                onClick = onSelectHot,
            )
        }
        item {
            CommunityFilterChip(
                label = "全部",
                selected = selection.mode == CommunityFeedMode.LATEST && selection.category == null,
                onClick = { onSelectLatest(null) },
            )
        }
        items(communityCategories) { category ->
            CommunityFilterChip(
                label = category,
                selected = selection.mode == CommunityFeedMode.LATEST && selection.category == category,
                onClick = { onSelectLatest(category) },
                modifier = Modifier.testTag("community-filter-$category"),
            )
        }
    }
}

/**
 * 无描边分类胶囊。
 *
 * 仍然是 Material `FilterChip`，因此点击、选中语义、涟漪与 48dp 命中都沿用组件自身实现；
 * 只替换颜色与形状：选中态用 accentSoft 底 + 品牌深绿字，未选中态用 surfaceContainer 底 +
 * 次级字色，层级由色阶而不是边框建立。文字改用 labelMedium，避免通用按钮字号把胶囊撑高。
 */
@Composable
private fun CommunityFilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
        modifier = modifier,
        shape = CircleShape,
        border = FilterChipDefaults.filterChipBorder(
            enabled = true,
            selected = selected,
            borderColor = Color.Transparent,
            selectedBorderColor = Color.Transparent,
        ),
        colors = FilterChipDefaults.filterChipColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
            labelColor = MaterialTheme.colorScheme.onSurfaceVariant,
            selectedContainerColor = MaterialTheme.leafySurfaces.accentSoft,
            selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
        ),
    )
}

@Composable
fun CommunityPostCard(post: PostDto, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Surface(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .testTag("community-post-${post.id}"),
        color = MaterialTheme.leafySurfaces.page,
        shape = MaterialTheme.shapes.small,
    ) {
        Column(modifier = Modifier.padding(LeafySpacing.card)) {
            // 帖首：作者保留在阅读起点，分类紧随其后。
            // 用 FlowRow 而不是定宽 Row：大字体或长分类时分类换到下一行，
            // 作者因此始终保留可见宽度，不会被分类挤没。
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
                verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = if (post.is_anonymous) "匿名" else post.author?.nickname ?: "北林同学",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                post.category?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.outline,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Spacer(modifier = Modifier.height(LeafySpacing.micro))
            Text(post.title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Spacer(modifier = Modifier.height(LeafySpacing.tiny))
            Text(
                post.body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            if (post.images.isNotEmpty()) {
                Spacer(modifier = Modifier.height(LeafySpacing.micro))
                CommunityPostCoverImage(images = post.images)
            }
            Spacer(modifier = Modifier.height(LeafySpacing.compact))
            // 帖尾：时间与互动计数是一组元信息，给每篇帖子一个稳定的阅读落点。
            // 同样用 FlowRow：200% 字体或长计数时换行，而不是把这一行挤到溢出。
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
                verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                val date = post.created_at.substringBefore('T').replace('-', '.')
                if (date.isNotBlank()) {
                    Text(
                        date,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.outline,
                        maxLines = 1,
                    )
                }
                Text("${post.like_count} 赞", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("${post.comment_count} 评论", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (post.viewer_has_favorited) {
                    Text("已收藏", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                }
            }
            Spacer(modifier = Modifier.height(LeafySpacing.compact))
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        }
    }
}
