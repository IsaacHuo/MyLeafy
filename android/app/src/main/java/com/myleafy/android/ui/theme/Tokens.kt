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
    /** 内容卡片的极淡投影；与 iOS `leafyCardStyle()` 的 2pt 投影对齐。 */
    val card = 2.dp
    val floating = 3.dp
    val modal = 6.dp
}

object LeafyStroke {
    val thin = 0.5.dp
    val hairline = 1.dp
    val progress = 2.dp
    val emphasis = 2.dp
}

/**
 * 弱化层的统一透明度。散落的 0.12/0.35/0.45/0.55 会让同一语义在不同页面深浅不一。
 */
object LeafyAlpha {
    /** 卡片描边，也是最弱的网格线。 */
    const val cardBorder = 0.12f
    /** 列表行分隔线。 */
    const val divider = 0.35f
    /** 输入框、导航栏等需要更明确边界的位置。 */
    const val border = 0.35f
    /** 次要图标（箭头、星标等）。 */
    const val mutedIcon = 0.55f
    /** 课程卡副文。 */
    const val subtitle = 0.82f
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
    /** 与 iOS `AppRadius.small` 对齐；空白格与课程块共用。 */
    val cellCornerRadius = 12.dp
    val dateIndicatorSize = 28.dp
    val currentTimeIndicator = 2.dp

    /**
     * 空白格只作为对齐参照，不再和课程块争夺注意力。
     * 无自定义背景时空格与页面同色，只留一条更淡的描边画出网格；
     * 有照片/纯色背景时才用半透明填充压住背景。
     */
    const val emptyCellBorderAlpha = 0.12f
    const val emptyCellFillAlphaOnBackground = 0.18f
    const val emptyCellBorderAlphaOnBackground = 0.18f
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
