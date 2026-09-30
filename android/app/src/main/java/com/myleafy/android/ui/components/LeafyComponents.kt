package com.myleafy.android.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScaffoldDefaults
import androidx.compose.material3.SheetState
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.clip
import com.myleafy.android.ui.theme.LeafyMotion
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyElevation
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LeafyRootTopBar(
    title: String,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    actions: @Composable RowScope.() -> Unit = {},
) {
    LeafyRootTopBar(
        titleContent = {
            Text(
                text = title,
                style = MaterialTheme.typography.headlineSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                softWrap = false,
            )
        },
        modifier = modifier,
        compact = compact,
        actions = actions,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LeafyRootTopBar(
    titleContent: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    actions: @Composable RowScope.() -> Unit = {},
) {
    TopAppBar(
        title = titleContent,
        actions = actions,
        modifier = modifier,
        expandedHeight = leafyTopBarHeight(compact = compact),
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.leafySurfaces.page,
            scrolledContainerColor = MaterialTheme.leafySurfaces.elevated,
        ),
    )
}

/**
 * TopBar 高度随系统字体缩放增长（上限 1.6 倍）。
 * 100% 字体保持 56dp（紧凑模式 48dp）；200% 字体不再裁切标题，也不会额外放大内边距。
 */
@Composable
private fun leafyTopBarHeight(compact: Boolean = false): Dp {
    val base = if (compact) LeafyComponentSize.topBarCompact else LeafyComponentSize.topBar
    return base * LocalDensity.current.fontScale.coerceIn(1f, 1.6f)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LeafySecondaryScaffold(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},
    contentWindowInsets: WindowInsets = ScaffoldDefaults.contentWindowInsets,
    snackbarHost: @Composable () -> Unit = {},
    embedded: Boolean = false,
    content: @Composable (Modifier) -> Unit,
) {
    if (embedded) {
        Column(modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, content = actions)
            content(Modifier.weight(1f).fillMaxWidth())
            snackbarHost()
        }
        return
    }
    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.leafySurfaces.page,
        contentWindowInsets = contentWindowInsets,
        snackbarHost = snackbarHost,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleLarge,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        softWrap = false,
                    )
                },
                navigationIcon = {
                    LeafyActionIconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "返回",
                        )
                    }
                },
                actions = actions,
                expandedHeight = leafyTopBarHeight(compact = true),
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.leafySurfaces.page,
                    scrolledContainerColor = MaterialTheme.leafySurfaces.elevated,
                ),
            )
        },
    ) { padding ->
        content(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .consumeWindowInsets(padding),
        )
    }
}

@Composable
fun LeafyActionIconButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier.size(LeafyIconSize.touchTarget),
        enabled = enabled,
        content = content,
    )
}

fun Modifier.leafyMinimumTouchTarget(): Modifier = sizeIn(
    minWidth = LeafyComponentSize.minimumTouchTarget,
    minHeight = LeafyComponentSize.minimumTouchTarget,
)

@Composable
fun LeafySectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    supportingText: String? = null,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny),
    ) {
        Text(text = title, style = MaterialTheme.typography.titleLarge)
        supportingText?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun LeafyContentSurface(
    modifier: Modifier = Modifier,
    elevated: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(
        modifier = modifier,
        color = if (elevated) MaterialTheme.leafySurfaces.elevated else MaterialTheme.leafySurfaces.content,
        shape = MaterialTheme.shapes.medium,
        tonalElevation = if (elevated) LeafyElevation.resting else LeafyElevation.flat,
        shadowElevation = LeafyElevation.flat,
    ) {
        Column(content = content)
    }
}

@Composable
fun LeafyToolRow(
    headlineContent: @Composable () -> Unit,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    supportingContent: (@Composable () -> Unit)? = null,
    leadingContent: (@Composable () -> Unit)? = null,
    trailingContent: (@Composable () -> Unit)? = null,
    minHeight: Dp = LeafyComponentSize.toolRowMinHeight,
) {
    Surface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().heightIn(min = minHeight),
        color = MaterialTheme.leafySurfaces.content,
        shape = MaterialTheme.shapes.medium,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = LeafySpacing.card, vertical = LeafySpacing.compact),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            leadingContent?.let {
                it()
                Spacer(modifier = Modifier.width(LeafySpacing.compact))
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny),
            ) {
                headlineContent()
                supportingContent?.invoke()
            }
            trailingContent?.let {
                Spacer(modifier = Modifier.width(LeafySpacing.micro))
                it()
            }
        }
    }
}

@Composable
fun LeafySettingsRow(
    headlineContent: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    supportingContent: (@Composable () -> Unit)? = null,
    leadingContent: (@Composable () -> Unit)? = null,
    trailingContent: (@Composable () -> Unit)? = null,
) {
    val rowContent: @Composable () -> Unit = {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = LeafyComponentSize.settingsRowMinHeight)
                .padding(horizontal = LeafySpacing.card, vertical = LeafySpacing.micro),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            leadingContent?.let {
                it()
                Spacer(modifier = Modifier.width(LeafySpacing.compact))
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny),
            ) {
                headlineContent()
                supportingContent?.invoke()
            }
            trailingContent?.let {
                Spacer(modifier = Modifier.width(LeafySpacing.micro))
                it()
            }
        }
    }
    if (onClick != null) {
        Surface(
            onClick = onClick,
            modifier = modifier.fillMaxWidth(),
            color = MaterialTheme.leafySurfaces.content,
            content = rowContent,
        )
    } else {
        Surface(
            modifier = modifier.fillMaxWidth(),
            color = MaterialTheme.leafySurfaces.content,
            content = rowContent,
        )
    }
}

@Composable
fun LeafyFeatureCard(
    title: String,
    description: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    trailingContent: (@Composable () -> Unit)? = null,
) {
    LeafyToolRow(
        headlineContent = { Text(text = title, style = MaterialTheme.typography.titleSmall) },
        supportingContent = {
            Text(
                text = description,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        leadingContent = {
            Surface(
                color = MaterialTheme.leafySurfaces.accentSoft,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                shape = MaterialTheme.shapes.small,
            ) {
                Box(
                    modifier = Modifier.size(LeafyComponentSize.featureIconContainer),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        modifier = Modifier.size(LeafyIconSize.standard),
                    )
                }
            }
        },
        onClick = onClick,
        modifier = modifier,
        trailingContent = trailingContent,
    )
}

@Composable
fun LeafyLoadingState(
    modifier: Modifier = Modifier,
    message: String? = null,
) {
    Column(
        modifier = modifier.fillMaxWidth().padding(LeafySpacing.section),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        CircularProgressIndicator(modifier = Modifier.size(LeafyIconSize.prominent))
        message?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
fun LeafyEmptyState(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    icon: ImageVector = Icons.Outlined.Info,
    action: (@Composable () -> Unit)? = null,
) {
    LeafyStateContent(
        title = title,
        message = message,
        icon = icon,
        modifier = modifier,
        iconContainerColor = MaterialTheme.leafySurfaces.accentSoft,
        iconContentColor = MaterialTheme.colorScheme.primary,
        action = action,
    )
}

@Composable
fun LeafyErrorState(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    action: (@Composable () -> Unit)? = null,
) {
    LeafyStateContent(
        title = title,
        message = message,
        icon = Icons.Outlined.Warning,
        modifier = modifier,
        iconContainerColor = MaterialTheme.colorScheme.errorContainer,
        iconContentColor = MaterialTheme.colorScheme.onErrorContainer,
        action = action,
    )
}

/** 空状态与错误状态共用同一版面，只有图标底板语义色不同。 */
@Composable
private fun LeafyStateContent(
    title: String,
    message: String,
    icon: ImageVector,
    iconContainerColor: Color,
    iconContentColor: Color,
    modifier: Modifier = Modifier,
    action: (@Composable () -> Unit)? = null,
) {
    // 外层铺满调用方给定的区域并水平居中，内层内容列再限宽。
    // 输出限宽必须写成 widthIn 在前、fillMaxWidth 在后：先收窄可用宽度再填充，
    // 反过来 fillMaxWidth 会把约束固定成父级宽度，widthIn 就不会生效。
    // 居中放在组件内部，这样调用方只传 fillMaxSize / fillMaxWidth 也能在宽屏对齐。
    Box(
        modifier = modifier.fillMaxWidth(),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = LeafyComponentSize.emptyStateMaxWidth)
                .fillMaxWidth()
                .padding(horizontal = LeafySpacing.section, vertical = LeafySpacing.section),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Surface(
                color = iconContainerColor,
                contentColor = iconContentColor,
                shape = MaterialTheme.shapes.large,
            ) {
                Box(
                    modifier = Modifier.size(LeafyIconSize.emptyStateContainer),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        modifier = Modifier.size(LeafyIconSize.standard),
                    )
                }
            }
            Spacer(modifier = Modifier.height(LeafySpacing.compact))
            Text(text = title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
            Spacer(modifier = Modifier.height(LeafySpacing.tiny))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            action?.let {
                Spacer(modifier = Modifier.height(LeafySpacing.card))
                it()
            }
        }
    }
}

@Composable
fun LeafyStatusBanner(
    message: String,
    isError: Boolean,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    onDismiss: (() -> Unit)? = null,
) {
    val container = if (isError) MaterialTheme.colorScheme.errorContainer else MaterialTheme.leafySurfaces.accentSoft
    val content = if (isError) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onPrimaryContainer
    val hasAction = actionLabel != null && onAction != null
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = container,
        contentColor = content,
        shape = MaterialTheme.shapes.medium,
    ) {
        // 没有操作时保持单行文案的原版式；带重试/关闭时才引入一行操作区，
        // 失败提示因此可以一直留在屏幕上，直到用户重试、成功或主动关闭。
        if (!hasAction && onDismiss == null) {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(LeafySpacing.compact),
            )
        } else {
            Row(
                modifier = Modifier.padding(
                    start = LeafySpacing.compact,
                    end = LeafySpacing.tiny,
                    top = LeafySpacing.tiny,
                    bottom = LeafySpacing.tiny,
                ),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = message,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f).padding(vertical = LeafySpacing.tiny),
                )
                if (hasAction) {
                    TextButton(
                        onClick = requireNotNull(onAction),
                        // 操作按横幅自身的语义色呈现：错误横幅上不再出现品牌绿按钮。
                        colors = ButtonDefaults.textButtonColors(contentColor = content),
                    ) {
                        Text(text = requireNotNull(actionLabel), style = MaterialTheme.typography.labelLarge)
                    }
                }
                onDismiss?.let { dismiss ->
                    IconButton(
                        onClick = dismiss,
                        modifier = Modifier.size(LeafyIconSize.touchTarget),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Close,
                            contentDescription = "关闭提示",
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun LeafySnackbarHost(
    hostState: SnackbarHostState,
    modifier: Modifier = Modifier,
) {
    SnackbarHost(hostState = hostState, modifier = modifier) { data ->
        Snackbar(
            snackbarData = data,
            shape = MaterialTheme.shapes.medium,
            containerColor = MaterialTheme.colorScheme.inverseSurface,
            contentColor = MaterialTheme.colorScheme.inverseOnSurface,
            actionColor = MaterialTheme.colorScheme.inversePrimary,
        )
    }
}

@Composable
fun LeafySheetContent(
    modifier: Modifier = Modifier,
    titleContent: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .imePadding()
            .padding(start = LeafySpacing.page, end = LeafySpacing.page, bottom = LeafySpacing.section),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.card),
    ) {
        titleContent?.invoke()
        content()
    }
}

object LeafyButtonDefaults {
    val shape
        @Composable get() = MaterialTheme.shapes.medium
    val contentPadding
        @Composable get() = ButtonDefaults.ContentPadding
    val elevation
        @Composable get() = ButtonDefaults.buttonElevation(defaultElevation = LeafyElevation.flat)
}

@Composable
fun LeafyPrimaryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale = animateFloatAsState(if (pressed && enabled) 0.98f else 1f, tween(LeafyMotion.quick), label = "button-press")
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = LeafyComponentSize.minimumTouchTarget).graphicsLayer { scaleX = scale.value; scaleY = scale.value },
        interactionSource = interaction,
        enabled = enabled,
        shape = LeafyButtonDefaults.shape,
        contentPadding = LeafyButtonDefaults.contentPadding,
        elevation = LeafyButtonDefaults.elevation,
        content = content,
    )
}

@Composable
fun LeafySecondaryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale = animateFloatAsState(if (pressed && enabled) 0.98f else 1f, tween(LeafyMotion.quick), label = "button-press")
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.heightIn(min = LeafyComponentSize.minimumTouchTarget).graphicsLayer { scaleX = scale.value; scaleY = scale.value },
        interactionSource = interaction,
        enabled = enabled,
        shape = LeafyButtonDefaults.shape,
        contentPadding = LeafyButtonDefaults.contentPadding,
        content = content,
    )
}

@Composable
fun LeafyTextButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    TextButton(
        onClick = onClick,
        modifier = modifier.heightIn(min = LeafyComponentSize.minimumTouchTarget),
        enabled = enabled,
        shape = LeafyButtonDefaults.shape,
        content = content,
    )
}

@Composable
fun LeafyDestructiveButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale = animateFloatAsState(if (pressed && enabled) 0.98f else 1f, tween(LeafyMotion.quick), label = "button-press")
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.heightIn(min = LeafyComponentSize.minimumTouchTarget).graphicsLayer { scaleX = scale.value; scaleY = scale.value },
        interactionSource = interaction,
        enabled = enabled,
        shape = LeafyButtonDefaults.shape,
        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
        contentPadding = LeafyButtonDefaults.contentPadding,
        content = content,
    )
}

@Composable
fun LeafySettingsDivider(modifier: Modifier = Modifier) {
    HorizontalDivider(
        modifier = modifier.padding(
            start = LeafyComponentSize.settingsIconContainer + LeafySpacing.card + LeafySpacing.compact,
        ),
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
    )
}

@Composable
fun LeafySettingsGroup(
    title: String,
    modifier: Modifier = Modifier,
    supportingText: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
    ) {
        Column(Modifier.padding(horizontal = LeafySpacing.card)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            supportingText?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.leafySurfaces.content) {
            Column(content = content)
        }
    }
}

@Composable
fun LeafyAdaptiveContent(
    modifier: Modifier = Modifier,
    maxWidth: Dp = LeafyComponentSize.contentMaxWidth,
    contentPadding: PaddingValues = PaddingValues(horizontal = LeafySpacing.page),
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier.fillMaxWidth(),
        contentAlignment = Alignment.TopCenter,
    ) {
        Box(
            modifier = Modifier
                .widthIn(max = maxWidth)
                .fillMaxWidth()
                .padding(contentPadding),
            content = content,
        )
    }
}

@Composable
fun LeafyAlertDialog(
    onDismissRequest: () -> Unit,
    confirmButton: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    dismissButton: (@Composable () -> Unit)? = null,
    title: (@Composable () -> Unit)? = null,
    text: (@Composable () -> Unit)? = null,
) {
    DeferUpdatePrompt()
    AlertDialog(
        onDismissRequest = onDismissRequest,
        confirmButton = confirmButton,
        modifier = modifier,
        dismissButton = dismissButton,
        title = title,
        text = text,
        shape = MaterialTheme.shapes.large,
        containerColor = MaterialTheme.leafySurfaces.modal,
        titleContentColor = MaterialTheme.colorScheme.onSurface,
        textContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LeafyModalBottomSheet(
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    sheetState: SheetState? = null,
    dragHandle: @Composable (() -> Unit)? = { BottomSheetDefaults.DragHandle() },
    content: @Composable ColumnScope.() -> Unit,
) {
    DeferUpdatePrompt()
    val resolvedSheetState = sheetState ?: rememberModalBottomSheetState()
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        modifier = modifier,
        sheetState = resolvedSheetState,
        shape = MaterialTheme.shapes.large,
        containerColor = MaterialTheme.leafySurfaces.modal,
        dragHandle = dragHandle,
        content = content,
    )
}
