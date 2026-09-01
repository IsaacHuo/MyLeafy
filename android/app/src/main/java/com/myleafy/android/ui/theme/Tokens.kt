package com.myleafy.android.ui.theme

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

object LeafySpacing {
    val hairline = 1.dp
    val tiny = 4.dp
    val micro = 8.dp
    val compact = 12.dp
    val card = 16.dp
    val page = 20.dp
    val section = 24.dp
    val spacious = 32.dp
    val rootTop = 16.dp
}

object LeafyElevation {
    val flat = 0.dp
    val resting = 1.dp
    val floating = 3.dp
    val modal = 6.dp
}

object LeafyIconSize {
    val compact = 18.dp
    val standard = 24.dp
    val prominent = 32.dp
    val touchTarget = 48.dp
    val emptyStateContainer = 56.dp
}

object LeafyComponentSize {
    val topBar = 56.dp
    val minimumTouchTarget = 48.dp
    val settingsIconContainer = 48.dp
    val contentMaxWidth = 720.dp
    val formMaxWidth = 420.dp
}

object LeafyMotion {
    const val quick = 120
    const val standard = 220
    const val emphasized = 320
    val easing = FastOutSlowInEasing
}

@Immutable
data class LeafySurfaceColors(
    val page: Color,
    val grouped: Color,
    val content: Color,
    val elevated: Color,
    val modal: Color,
    val accentSoft: Color,
)

@Immutable
data class LeafyCourseColors(
    val containers: List<Color>,
    val content: Color,
)
