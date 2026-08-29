package com.myleafy.android.features.community

import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.campus.ActiveCampusContext
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.shared.model.PostDto
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafyStatusBanner

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
                campusId = ActiveCampusContext.descriptor.id.rawValue,
            )
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

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
                        Icon(Icons.Outlined.Notifications, contentDescription = "社区通知")
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
        when (val state = uiState) {
            is CommunityUiState.Loading -> {
                Column(
                    modifier = Modifier.fillMaxSize().padding(contentPadding),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator(modifier = Modifier.padding(top = 32.dp))
                }
            }

            is CommunityUiState.Error -> {
                Column(
                    modifier = Modifier.fillMaxSize().padding(contentPadding).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    LeafyStatusBanner(message = state.message, isError = true)
                    Text(
                        text = "社区依赖 MyLeafy 后端配置。未配置或网络不可达时不会显示模拟内容。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(onClick = viewModel::refresh) { Text("重试") }
                }
            }

            is CommunityUiState.Loaded -> {
                if (state.posts.isEmpty()) {
                    LeafyEmptyState(
                        title = "社区暂时没有内容",
                        message = "这里会显示当前校园的真实帖子。你也可以发布第一条内容。",
                        icon = Icons.Outlined.Forum,
                        modifier = Modifier.padding(contentPadding),
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize().padding(contentPadding),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(
                            start = 16.dp,
                            end = 16.dp,
                            top = 4.dp,
                            bottom = 96.dp,
                        ),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        item {
                            Text(
                                text = "校园动态",
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                        items(state.posts, key = { it.id }) { post ->
                            PostRow(post, onClick = { onPostClick(post.id) })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PostRow(post: PostDto, onClick: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = post.author?.nickname ?: "匿名",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = post.title,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = post.body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(modifier = Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(
                    text = "${post.like_count} 赞",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = "${post.comment_count} 评论",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
