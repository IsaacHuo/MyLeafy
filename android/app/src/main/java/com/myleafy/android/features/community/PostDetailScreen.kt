package com.myleafy.android.features.community

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import com.myleafy.android.ui.components.LeafyTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.shared.model.CommentThread
import com.myleafy.android.shared.model.CommentThreadDto
import com.myleafy.android.shared.model.communityDisplayName
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyErrorState
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryButton
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafyStroke
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
    val writeAction = rememberCommunityWriteAction()
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
                onLike = { writeAction(viewModel::toggleLike) },
                onFavorite = { writeAction(viewModel::toggleFavorite) },
                onComment = { body, parent, reply -> writeAction { viewModel.createComment(body, parent, reply) } },
                onCommentLike = viewModel::toggleCommentLike,
                onLoadMoreComments = viewModel::loadMoreComments,
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
    onCommentLike: (String) -> Unit,
    onLoadMoreComments: () -> Unit,
    onConfirm: (PendingConfirmation) -> Unit,
    onClearMessage: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var commentInput by remember { mutableStateOf("") }
    var replyTarget by remember { mutableStateOf<CommentThreadDto?>(null) }
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(horizontal = LeafySpacing.card),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        item {
            LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(LeafySpacing.card)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = if (state.post.is_anonymous) "匿名" else state.post.author?.communityDisplayName() ?: "北林同学",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.weight(1f),
                        )
                        PostMenu(
                            isOwner = state.post.author_id == state.currentProfileId,
                            canBlock = !state.post.is_anonymous && state.post.author_id != state.currentProfileId,
                            authorId = state.post.author_id,
                            postId = state.post.id,
                            postTitle = state.post.title,
                            enabled = state.pendingModerationTarget == null,
                            onConfirm = onConfirm,
                        )
                    }
                    Spacer(Modifier.height(LeafySpacing.micro))
                    Text(state.post.title, style = MaterialTheme.typography.titleLarge)
                    Spacer(Modifier.height(LeafySpacing.micro))
                    Text(state.post.body, style = MaterialTheme.typography.bodyLarge)
                    if (state.post.images.isNotEmpty()) {
                        Spacer(Modifier.height(LeafySpacing.compact))
                        CommunityPostImageColumn(images = state.post.images)
                    }
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
            replyTarget?.let { target ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "回复 ${target.author?.communityDisplayName() ?: "同学"}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.weight(1f),
                    )
                    LeafyTextButton(onClick = { replyTarget = null }) { Text("取消") }
                }
            }
            Spacer(Modifier.height(LeafySpacing.micro))
            Row(verticalAlignment = Alignment.CenterVertically) {
                LeafyTextField(
                    value = commentInput,
                    onValueChange = { commentInput = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text(if (replyTarget == null) "写评论…" else "回复…") },
                    minLines = 1,
                    maxLines = 3,
                )
                Spacer(Modifier.width(LeafySpacing.micro))
                LeafyPrimaryButton(
                    onClick = {
                        val target = replyTarget
                        onComment(commentInput, target?.parent_comment_id ?: target?.id, target?.id)
                        commentInput = ""
                        replyTarget = null
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
                pendingLikes = state.commentLikePending,
                onReply = { replyTarget = it },
                onCommentLike = onCommentLike,
                onConfirm = onConfirm,
            )
        }
        if (state.commentLoadError != null) {
            item {
                LeafyStatusBanner(
                    message = state.commentLoadError,
                    isError = true,
                    actionLabel = "重试",
                    onAction = onLoadMoreComments,
                )
            }
        }
        if (state.hasMoreComments || state.isLoadingMoreComments) {
            item {
                LeafySecondaryButton(
                    onClick = onLoadMoreComments,
                    enabled = !state.isLoadingMoreComments,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (state.isLoadingMoreComments) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(LeafyIconSize.compact),
                            strokeWidth = LeafyStroke.progress,
                        )
                        Text("加载中…", modifier = Modifier.padding(start = LeafySpacing.micro))
                    } else {
                        Text("加载更多评论")
                    }
                }
            }
        }
        item { Spacer(Modifier.height(LeafySpacing.card)) }
    }
}

@Composable
private fun PostMenu(
    isOwner: Boolean,
    canBlock: Boolean,
    authorId: String,
    postId: String,
    postTitle: String,
    enabled: Boolean,
    onConfirm: (PendingConfirmation) -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var expanded by remember { mutableStateOf(false) }
    LeafyActionIconButton(onClick = { expanded = true }, enabled = enabled) {
        Icon(Icons.Outlined.MoreVert, contentDescription = "帖子操作")
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        DropdownMenuItem(text = { Text("分享帖子") }, onClick = {
            expanded = false
            val share = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(
                    android.content.Intent.EXTRA_TEXT,
                    "$postTitle\nmyleafy://community-post?id=$postId",
                )
            }
            context.startActivity(android.content.Intent.createChooser(share, "分享帖子"))
        })
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
    pendingLikes: Set<String>,
    onReply: (CommentThreadDto) -> Unit,
    onCommentLike: (String) -> Unit,
    onConfirm: (PendingConfirmation) -> Unit,
) {
    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(LeafySpacing.compact)) {
            CommentLine(
                comment = thread.root,
                currentProfileId = currentProfileId,
                menuEnabled = menusEnabled,
                pendingLike = thread.root.id in pendingLikes,
                onReply = onReply,
                onCommentLike = onCommentLike,
                onConfirm = onConfirm,
            )
            thread.replies.forEach { reply ->
                Row(modifier = Modifier.padding(start = LeafySpacing.page, top = LeafySpacing.micro)) {
                    Text("↳", color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(end = LeafySpacing.tiny))
                    CommentLine(
                        comment = reply,
                        currentProfileId = currentProfileId,
                        menuEnabled = menusEnabled,
                        pendingLike = reply.id in pendingLikes,
                        onReply = onReply,
                        onCommentLike = onCommentLike,
                        onConfirm = onConfirm,
                    )
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
    pendingLike: Boolean,
    onReply: (CommentThreadDto) -> Unit,
    onCommentLike: (String) -> Unit,
    onConfirm: (PendingConfirmation) -> Unit,
) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (!comment.is_deleted_placeholder) {
                    CommunityAvatar(
                        name = if (comment.is_anonymous) "匿名" else comment.author?.communityDisplayName() ?: "北林同学",
                        url = comment.author?.avatar_url ?: comment.author?.signed_avatar_url,
                        size = 18.dp,
                    )
                }
                Text(
                    text = when {
                        comment.is_deleted_placeholder -> "（已删除）"
                        comment.is_anonymous -> "匿名"
                        else -> comment.author?.communityDisplayName() ?: "北林同学"
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = if (comment.is_deleted_placeholder) Modifier else Modifier.padding(start = 6.dp),
                )
            }
            if (!comment.is_deleted_placeholder && comment.reply_target_is_visible) {
                comment.reply_to_author?.let { target ->
                    Text(
                        text = "回复 ${target.communityDisplayName()}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            Text(
                if (comment.is_deleted_placeholder) comment.body.ifBlank { "该评论已删除" } else comment.body,
                style = MaterialTheme.typography.bodyMedium,
                color = if (comment.is_deleted_placeholder) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
            )
            if (!comment.is_deleted_placeholder) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
                ) {
                    LeafyTextButton(onClick = { onReply(comment) }) { Text("回复") }
                    LeafyTextButton(
                        onClick = { onCommentLike(comment.id) },
                        enabled = !pendingLike,
                    ) {
                        Icon(
                            imageVector = if (comment.viewer_has_liked) {
                                Icons.Filled.Favorite
                            } else {
                                Icons.Outlined.FavoriteBorder
                            },
                            contentDescription = if (comment.viewer_has_liked) "取消点赞" else "点赞评论",
                            tint = if (comment.viewer_has_liked) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                            modifier = Modifier.size(LeafyIconSize.compact),
                        )
                        if (comment.like_count > 0) {
                            Text(
                                text = comment.like_count.toString(),
                                modifier = Modifier.padding(start = LeafySpacing.tiny),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        }
                    }
                }
            }
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
