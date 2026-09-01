package com.myleafy.android.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScaffoldDefaults
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
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
    actions: @Composable RowScope.() -> Unit = {},
) {
    TopAppBar(
        title = { Text(text = title, style = MaterialTheme.typography.headlineSmall) },
        actions = actions,
        modifier = modifier,
        expandedHeight = LeafyComponentSize.topBar,
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.leafySurfaces.page,
            scrolledContainerColor = MaterialTheme.leafySurfaces.elevated,
        ),
    )
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
    content: @Composable (Modifier) -> Unit,
) {
    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.leafySurfaces.page,
        contentWindowInsets = contentWindowInsets,
        snackbarHost = snackbarHost,
        topBar = {
            TopAppBar(
                title = { Text(title, style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    LeafyActionIconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "返回",
                        )
                    }
                },
                actions = actions,
                expandedHeight = LeafyComponentSize.topBar,
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
) {
    Surface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().heightIn(min = 72.dp),
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
                .heightIn(min = 64.dp)
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
                    modifier = Modifier.size(LeafyComponentSize.settingsIconContainer),
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
    Column(
        modifier = modifier
            .fillMaxWidth()
            .widthIn(max = 520.dp)
            .padding(horizontal = LeafySpacing.section, vertical = LeafySpacing.spacious),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
    ) {
        Surface(
            color = MaterialTheme.leafySurfaces.accentSoft,
            contentColor = MaterialTheme.colorScheme.primary,
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
        Text(text = title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        action?.invoke()
    }
}

@Composable
fun LeafyErrorState(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    action: (@Composable () -> Unit)? = null,
) {
    LeafyEmptyState(
        title = title,
        message = message,
        modifier = modifier,
        icon = Icons.Outlined.Info,
        action = action,
    )
}

@Composable
fun LeafyStatusBanner(
    message: String,
    isError: Boolean,
    modifier: Modifier = Modifier,
) {
    val container = if (isError) MaterialTheme.colorScheme.errorContainer else MaterialTheme.leafySurfaces.accentSoft
    val content = if (isError) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onPrimaryContainer
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = container,
        contentColor = content,
        shape = MaterialTheme.shapes.medium,
    ) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(LeafySpacing.compact),
        )
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
