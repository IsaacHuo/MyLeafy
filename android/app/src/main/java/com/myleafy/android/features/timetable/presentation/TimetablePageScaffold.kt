package com.myleafy.android.features.timetable.presentation

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.theme.leafySurfaces

/** The real timetable chrome, independent of authentication and repositories. */
@Composable
@OptIn(ExperimentalMaterial3Api::class)
internal fun TimetablePageScaffold(
    titleContent: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    background: TimetableBackgroundSettings = TimetableBackgroundSettings(),
    actions: @Composable RowScope.() -> Unit = {},
    snackbarHost: @Composable () -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    Scaffold(
        modifier = modifier,
        containerColor = Color.Transparent,
        snackbarHost = snackbarHost,
        topBar = {
            LeafyRootTopBar(
                titleContent = titleContent, compact = true, actions = actions,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                    scrolledContainerColor = MaterialTheme.leafySurfaces.elevated.copy(alpha = 0.94f),
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    actionIconContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        },
        content = content,
    )
}
