package com.myleafy.android.navigation

import androidx.compose.runtime.Composable
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.unit.dp
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.features.timetable.presentation.TimetablePageBackdrop
import com.myleafy.android.ui.theme.leafySurfaces

/** The personalized surface belongs only to the timetable root; decoding belongs to this shell. */
@Composable
internal fun TimetableNavigationScaffold(
    background: TimetableBackgroundSettings,
    selectedTab: RootTab,
    onTabSelected: (RootTab) -> Unit,
    modifier: Modifier = Modifier,
    showNavigation: Boolean = true,
    content: @Composable () -> Unit,
) {
    val visible = showNavigation && selectedTab == RootTab.TIMETABLE
    val page = MaterialTheme.leafySurfaces.page
    val surface = if (visible && background.enabled) LeafyNavigationSurface(
        color = MaterialTheme.leafySurfaces.elevated.copy(alpha = if (page.luminance() < 0.5f) 0.56f else 0.42f),
        borderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.12f),
        elevation = 0.dp,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) else null
    LeafyNavigationScaffold(
        selectedTab = selectedTab,
        onTabSelected = onTabSelected,
        modifier = modifier,
        showNavigation = showNavigation,
        backgroundContent = {
            TimetablePageBackdrop(background, visible, Modifier.matchParentSize())
        },
        navigationSurface = surface,
        content = content,
    )
}
