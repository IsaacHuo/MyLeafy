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

object LeafyStroke {
    val progress = 2.dp
    val emphasis = 2.dp
}

object LeafyGesture {
    val pullRefreshThreshold = 72.dp
}

object LeafyTimetableTokens {
    /** 竖排时间轴的最小宽度，实际宽度由系统字体测量得出。 */
    val axisWidth = 32.dp
    val minimumPeriodRowHeight = 1.dp
    val maximumPeriodRowHeight = 56.dp
    val gridGap = 2.dp
    val cellCornerRadius = 8.dp
    val dateIndicatorSize = 28.dp
    val currentTimeIndicator = 2.dp

    /**
     * 空白格只作为对齐参照，不再和课程块争夺注意力。
     * 无自定义背景时空格与页面同色，只留一条更淡的描边画出网格；
     * 有照片/纯色背景时才用半透明填充压住背景。
     */
    const val emptyCellBorderAlpha = 0.18f
    const val emptyCellFillAlphaOnBackground = 0.22f
    const val emptyCellBorderAlphaOnBackground = 0.25f
}

object LeafyAdaptiveTokens {
    val twoPaneBreakpoint = 600.dp
    val campusSidebarWidth = 184.dp
}

object LeafyLoginTokens {
    val captchaWidth = 96.dp
}

object LeafyIconSize {
    val compact = 18.dp
    val standard = 24.dp
    val prominent = 32.dp
    val touchTarget = 48.dp
    val emptyStateContainer = 48.dp
}

object LeafyComponentSize {
    val topBar = 56.dp
    val topBarCompact = 48.dp
    val minimumTouchTarget = 48.dp
    val featureIconContainer = 40.dp
    val settingsIconContainer = 32.dp
    val settingsRowMinHeight = 56.dp
    val toolRowMinHeight = 72.dp
    /** 校园紧凑入口行：24dp 图标 + 标题，行高最低 64dp，大字体自然增高。 */
    val compactToolRowMinHeight = 64.dp
    val contentMaxWidth = 720.dp
    val formMaxWidth = 420.dp
    val floatingActionClearance = 96.dp
    val emptyStateMaxWidth = 520.dp
    val timetableNavigation = 40.dp
}

object LeafyMotion {
    const val quick = 120
    const val standard = 220
    const val emphasized = 240
    val easing = androidx.compose.animation.core.CubicBezierEasing(0.23f, 1f, 0.32f, 1f)
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
