package com.myleafy.android.features.community

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.shared.model.CommentThread
import com.myleafy.android.shared.model.CommentThreadDto
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyStatusBanner

@Composable
fun PostDetailScreen(
    postId: String,
    onBack: () -> Unit,
    viewModel: PostDetailViewModel = viewModel(
        key = "post-$postId",
        factory = appViewModelFactory { container ->
            PostDetailViewModel(repository = container.communityRepository, postId = postId)
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

    LeafySecondaryScaffold(title = "帖子详情", onBack = onBack, modifier = modifier) { contentModifier ->
        Column(
            modifier = contentModifier
                .fillMaxSize()
                .padding(horizontal = 20.dp),
        ) {
            Spacer(modifier = Modifier.height(8.dp))

        when (val state = uiState) {
            is PostDetailUiState.Loading -> {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            }

            is PostDetailUiState.Error -> {
                Text(
                    text = state.message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
                Spacer(modifier = Modifier.height(8.dp))
                Button(onClick = viewModel::load) { Text("重试") }
            }

            is PostDetailUiState.Loaded -> {
                var commentInput by remember { mutableStateOf("") }
                LazyColumn {
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                    text = state.post.author?.nickname ?: "匿名",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Spacer(modifier = Modifier.height(6.dp))
                                Text(text = state.post.title, style = MaterialTheme.typography.titleMedium)
                                Spacer(modifier = Modifier.height(6.dp))
                                Text(
                                    text = state.post.body,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                                Spacer(modifier = Modifier.height(12.dp))
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    IconButton(
                                        onClick = viewModel::toggleLike,
                                        enabled = !state.isLikePending,
                                    ) {
                                        Icon(
                                            imageVector = if (state.post.viewer_has_liked) {
                                                Icons.Filled.ThumbUp
                                            } else {
                                                Icons.Outlined.ThumbUp
                                            },
                                            contentDescription = "点赞",
                                            tint = if (state.post.viewer_has_liked) {
                                                MaterialTheme.colorScheme.primary
                                            } else {
                                                MaterialTheme.colorScheme.onSurfaceVariant
                                            },
                                        )
                                    }
                                    Text(
                                        text = "${state.post.like_count} 赞 · ${state.post.comment_count} 评论",
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(text = "评论", style = MaterialTheme.typography.titleSmall)
                        Spacer(modifier = Modifier.height(8.dp))

                        state.mutationError?.let {
                            LeafyStatusBanner(message = it, isError = true)
                            Spacer(modifier = Modifier.height(8.dp))
                        }

                        Row(verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(
                                value = commentInput,
                                onValueChange = { commentInput = it },
                                modifier = Modifier.weight(1f),
                                placeholder = { Text("写评论…") },
                                singleLine = true,
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Button(
                                onClick = {
                                    viewModel.createComment(body = commentInput)
                                },
                                enabled = commentInput.isNotBlank() && !state.isCommentPending,
                            ) {
                                Text(if (state.isCommentPending) "发送中" else "发送")
                            }
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                    }

                    if (state.threads.isEmpty()) {
                        item {
                            Text(
                                text = "暂无评论",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.outline,
                            )
                        }
                    }
                    items(state.threads, key = { it.root.id }) { thread ->
                        CommentThreadRow(thread)
                    }
                }
            }
            }
        }
    }
}

@Composable
private fun CommentThreadRow(thread: CommentThread) {
    Card(modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
        Column(modifier = Modifier.padding(12.dp)) {
            CommentLine(thread.root)
            thread.replies.forEach { reply ->
                Row(modifier = Modifier.padding(start = 20.dp, top = 4.dp)) {
                    Text(text = "↳", color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(end = 4.dp))
                    Column {
                        CommentLine(reply)
                    }
                }
            }
        }
    }
}

@Composable
private fun CommentLine(comment: CommentThreadDto) {
    Column {
        Text(
            text = if (comment.is_deleted_placeholder) "（已删除）" else "匿名",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (comment.is_deleted_placeholder) {
            Text(
                text = comment.body.ifEmpty { "该评论已删除" },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline,
            )
        } else {
            Text(
                text = comment.body,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}
