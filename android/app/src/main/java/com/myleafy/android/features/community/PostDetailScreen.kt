package com.myleafy.android.features.community

import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.shared.model.CommentThread
import com.myleafy.android.shared.model.CommentThreadDto
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyErrorState
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafySpacing

private enum class ConfirmationKind { DELETE_POST, DELETE_COMMENT, REPORT_POST, REPORT_COMMENT, BLOCK_USER }
private data class PendingConfirmation(val kind: ConfirmationKind, val targetId: String)

@Composable
fun PostDetailScreen(
    postId: String,
    onBack: () -> Unit,
    onRemoved: () -> Unit = onBack,
    viewModel: PostDetailViewModel = viewModel(
        key = "post-$postId",
        factory = appViewModelFactory { container ->
            PostDetailViewModel(repository = container.communityRepository, postId = postId)
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var confirmation by remember { mutableStateOf<PendingConfirmation?>(null) }

    LaunchedEffect((uiState as? PostDetailUiState.Loaded)?.shouldClose) {
        if ((uiState as? PostDetailUiState.Loaded)?.shouldClose == true) onRemoved()
    }

    confirmation?.let { pending ->
        val (title, message) = when (pending.kind) {
            ConfirmationKind.DELETE_POST -> "删除帖子" to "帖子会被软删除，其他用户将无法再看到。"
            ConfirmationKind.DELETE_COMMENT -> "删除评论" to "评论会被标记为已删除。"
            ConfirmationKind.REPORT_POST -> "举报帖子" to "将以“其他违规”提交给社区审核。"
            ConfirmationKind.REPORT_COMMENT -> "举报评论" to "将以“其他违规”提交给社区审核。"
            ConfirmationKind.BLOCK_USER -> "屏蔽用户" to "屏蔽后，动态列表将不再显示该用户的内容。"
        }
        LeafyAlertDialog(
            onDismissRequest = { confirmation = null },
            title = { Text(title) },
            text = { Text(message) },
            confirmButton = {
                LeafyTextButton(onClick = {
                    when (pending.kind) {
                        ConfirmationKind.DELETE_POST -> viewModel.deletePost()
                        ConfirmationKind.DELETE_COMMENT -> viewModel.deleteComment(pending.targetId)
                        ConfirmationKind.REPORT_POST -> viewModel.reportPost("其他违规")
                        ConfirmationKind.REPORT_COMMENT -> viewModel.reportComment(pending.targetId, "其他违规")
                        ConfirmationKind.BLOCK_USER -> viewModel.blockUser(pending.targetId)
                    }
                    confirmation = null
                }) { Text("确认") }
            },
            dismissButton = { LeafyTextButton(onClick = { confirmation = null }) { Text("取消") } },
        )
    }

    LeafySecondaryScaffold(title = "帖子详情", onBack = onBack, modifier = modifier) { contentModifier ->
        when (val state = uiState) {
            is PostDetailUiState.Loading -> LeafyLoadingState(
                modifier = contentModifier.fillMaxSize(),
                message = "正在加载帖子",
            )

            is PostDetailUiState.Error -> LeafyErrorState(
                title = "帖子暂时无法加载",
                message = state.message,
                modifier = contentModifier.fillMaxSize(),
                action = { LeafyPrimaryButton(onClick = viewModel::load) { Text("重试") } },
            )

            is PostDetailUiState.Loaded -> PostDetailContent(
                state = state,
                onLike = viewModel::toggleLike,
                onFavorite = viewModel::toggleFavorite,
                onComment = viewModel::createComment,
                onConfirm = { confirmation = it },
                onClearMessage = viewModel::clearMessage,
                modifier = contentModifier,
            )
        }
    }
}

@Composable
private fun PostDetailContent(
    state: PostDetailUiState.Loaded,
    onLike: () -> Unit,
    onFavorite: () -> Unit,
    onComment: (String, String?, String?) -> Unit,
    onConfirm: (PendingConfirmation) -> Unit,
    onClearMessage: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var commentInput by remember { mutableStateOf("") }
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(horizontal = LeafySpacing.card),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        item {
            LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(LeafySpacing.card)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = if (state.post.is_anonymous) "匿名" else state.post.author?.nickname ?: "北林同学",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.weight(1f),
                        )
                        PostMenu(
                            isOwner = state.post.author_id == state.currentProfileId,
                            canBlock = !state.post.is_anonymous && state.post.author_id != state.currentProfileId,
                            authorId = state.post.author_id,
                            enabled = state.pendingModerationTarget == null,
                            onConfirm = onConfirm,
                        )
                    }
                    Spacer(Modifier.height(LeafySpacing.micro))
                    Text(state.post.title, style = MaterialTheme.typography.titleLarge)
                    Spacer(Modifier.height(LeafySpacing.micro))
                    Text(state.post.body, style = MaterialTheme.typography.bodyLarge)
                    Spacer(Modifier.height(LeafySpacing.compact))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        LeafyActionIconButton(
                            onClick = onLike,
                            enabled = !state.isLikePending && !state.isFavoritePending && state.pendingModerationTarget == null,
                        ) {
                            Icon(
                                if (state.post.viewer_has_liked) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp,
                                contentDescription = if (state.post.viewer_has_liked) "取消点赞" else "点赞",
                                tint = if (state.post.viewer_has_liked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        LeafyActionIconButton(
                            onClick = onFavorite,
                            enabled = !state.isFavoritePending && !state.isLikePending && state.pendingModerationTarget == null,
                        ) {
                            Icon(
                                if (state.post.viewer_has_favorited) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                                contentDescription = if (state.post.viewer_has_favorited) "取消收藏" else "收藏",
                                tint = if (state.post.viewer_has_favorited) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(
                            "${state.post.like_count} 赞 · ${state.post.comment_count} 评论",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
        state.mutationError?.let { message ->
            item { LeafyStatusBanner(message = message, isError = true) }
        }
        state.mutationMessage?.let { message ->
            item {
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(
                            horizontal = LeafySpacing.card,
                            vertical = LeafySpacing.compact,
                        ),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(message, modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.primary)
                        LeafyTextButton(onClick = onClearMessage) { Text("知道了") }
                    }
                }
            }
        }
        item {
            Text("评论", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(LeafySpacing.micro))
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = commentInput,
                    onValueChange = { commentInput = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("写评论…") },
                    singleLine = true,
                )
                Spacer(Modifier.width(LeafySpacing.micro))
                LeafyPrimaryButton(
                    onClick = {
                        onComment(commentInput, null, null)
                    },
                    enabled = commentInput.isNotBlank() && !state.isCommentPending && state.pendingModerationTarget == null,
                ) { Text(if (state.isCommentPending) "发送中" else "发送") }
            }
        }
        if (state.threads.isEmpty()) {
            item { Text("暂无评论", color = MaterialTheme.colorScheme.outline) }
        }
        items(state.threads, key = { it.root.id }) { thread ->
            CommentThreadCard(
                thread,
                state.currentProfileId,
                menusEnabled = state.pendingModerationTarget == null,
                onConfirm = onConfirm,
            )
        }
        item { Spacer(Modifier.height(LeafySpacing.card)) }
    }
}

@Composable
private fun PostMenu(
    isOwner: Boolean,
    canBlock: Boolean,
    authorId: String,
    enabled: Boolean,
    onConfirm: (PendingConfirmation) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    LeafyActionIconButton(onClick = { expanded = true }, enabled = enabled) {
        Icon(Icons.Outlined.MoreVert, contentDescription = "帖子操作")
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        if (isOwner) {
            DropdownMenuItem(text = { Text("删除帖子") }, onClick = {
                expanded = false
                onConfirm(PendingConfirmation(ConfirmationKind.DELETE_POST, authorId))
            })
        } else {
            DropdownMenuItem(text = { Text("举报帖子") }, onClick = {
                expanded = false
                onConfirm(PendingConfirmation(ConfirmationKind.REPORT_POST, authorId))
            })
            if (canBlock) {
                DropdownMenuItem(text = { Text("屏蔽该用户") }, onClick = {
                    expanded = false
                    onConfirm(PendingConfirmation(ConfirmationKind.BLOCK_USER, authorId))
                })
            }
        }
    }
}

@Composable
private fun CommentThreadCard(
    thread: CommentThread,
    currentProfileId: String,
    menusEnabled: Boolean,
    onConfirm: (PendingConfirmation) -> Unit,
) {
    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(LeafySpacing.compact)) {
            CommentLine(thread.root, currentProfileId, menusEnabled, onConfirm)
            thread.replies.forEach { reply ->
                Row(modifier = Modifier.padding(start = LeafySpacing.page, top = LeafySpacing.micro)) {
                    Text("↳", color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(end = LeafySpacing.tiny))
                    CommentLine(reply, currentProfileId, menusEnabled, onConfirm)
                }
            }
        }
    }
}

@Composable
private fun CommentLine(
    comment: CommentThreadDto,
    currentProfileId: String,
    menuEnabled: Boolean,
    onConfirm: (PendingConfirmation) -> Unit,
) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                if (comment.is_deleted_placeholder) "（已删除）" else if (comment.is_anonymous) "匿名" else "北林同学",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                if (comment.is_deleted_placeholder) comment.body.ifBlank { "该评论已删除" } else comment.body,
                style = MaterialTheme.typography.bodyMedium,
                color = if (comment.is_deleted_placeholder) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
            )
        }
        if (!comment.is_deleted_placeholder) {
            var expanded by remember { mutableStateOf(false) }
            LeafyActionIconButton(onClick = { expanded = true }, enabled = menuEnabled) {
                Icon(Icons.Outlined.MoreVert, contentDescription = "评论操作")
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                if (comment.author_id == currentProfileId) {
                    DropdownMenuItem(text = { Text("删除评论") }, onClick = {
                        expanded = false
                        onConfirm(PendingConfirmation(ConfirmationKind.DELETE_COMMENT, comment.id))
                    })
                } else {
                    DropdownMenuItem(text = { Text("举报评论") }, onClick = {
                        expanded = false
                        onConfirm(PendingConfirmation(ConfirmationKind.REPORT_COMMENT, comment.id))
                    })
                    if (!comment.is_anonymous) {
                        DropdownMenuItem(text = { Text("屏蔽该用户") }, onClick = {
                            expanded = false
                            onConfirm(PendingConfirmation(ConfirmationKind.BLOCK_USER, comment.author_id))
                        })
                    }
                }
            }
        }
    }
}
