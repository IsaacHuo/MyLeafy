package com.myleafy.android.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

// 中英文混排基线：关闭字体自带上下留白，行高在行盒内居中。
// 中文与拉丁字形因此在同一行盒里对齐，列表与网格的行距不再随内容脚本变化。
private val LeafyPlatformStyle = PlatformTextStyle(includeFontPadding = false)
private val LeafyLineHeightStyle = LineHeightStyle(
    alignment = LineHeightStyle.Alignment.Center,
    trim = LineHeightStyle.Trim.None,
)

// 字距：汉字自带边距，正文与标题保持 0 最稳；仅拉丁/数字为主的小号标签保留少量字距。
private object LeafyTracking {
    val plain = 0.sp
    val label = 0.1.sp
    val micro = 0.4.sp
}

private fun leafyTextStyle(
    fontSize: TextUnit,
    lineHeight: TextUnit,
    fontWeight: FontWeight,
    letterSpacing: TextUnit = LeafyTracking.plain,
): TextStyle = TextStyle(
    fontSize = fontSize,
    lineHeight = lineHeight,
    fontWeight = fontWeight,
    letterSpacing = letterSpacing,
    platformStyle = LeafyPlatformStyle,
    lineHeightStyle = LeafyLineHeightStyle,
)

val MyLeafyTypography = Typography(
    displaySmall = leafyTextStyle(32.sp, 40.sp, FontWeight.Bold),
    headlineSmall = leafyTextStyle(26.sp, 34.sp, FontWeight.SemiBold),
    titleLarge = leafyTextStyle(20.sp, 28.sp, FontWeight.SemiBold),
    titleMedium = leafyTextStyle(18.sp, 24.sp, FontWeight.SemiBold),
    titleSmall = leafyTextStyle(16.sp, 22.sp, FontWeight.SemiBold),
    bodyLarge = leafyTextStyle(16.sp, 24.sp, FontWeight.Normal),
    bodyMedium = leafyTextStyle(14.sp, 20.sp, FontWeight.Normal),
    bodySmall = leafyTextStyle(11.sp, 16.sp, FontWeight.Normal),
    labelLarge = leafyTextStyle(16.sp, 22.sp, FontWeight.SemiBold, LeafyTracking.label),
    labelMedium = leafyTextStyle(14.sp, 20.sp, FontWeight.Medium, LeafyTracking.label),
    labelSmall = leafyTextStyle(11.sp, 16.sp, FontWeight.Medium, LeafyTracking.micro),
)

/**
 * 课表网格专用紧凑文字角色。
 *
 * 课表要在单屏内容纳 5/7 天 × 13 节，列宽随天数与冲突车道收缩，
 * 因此不复用通用 Typography：labelMedium / labelSmall 属于按钮与标签语义，
 * 而且 14sp 在冲突窄列放不下。页面只消费这里的样式，
 * 不再自行 copy(fontSize / lineHeight)。
 */
object LeafyTimetableType {
    /** 课程名：单节、行高紧张的格子。 */
    val courseTitle = leafyTextStyle(11.sp, 14.sp, FontWeight.SemiBold)

    /** 课程名：跨节或行高充足的格子。 */
    val courseTitleLarge = leafyTextStyle(14.sp, 18.sp, FontWeight.SemiBold)

    /** 副文：地点、教师。 */
    val courseSubtitle = leafyTextStyle(10.sp, 13.sp, FontWeight.Medium)

    /** 次副文：备注、周次；窄列可整段省略。 */
    val courseMeta = leafyTextStyle(12.sp, 16.sp, FontWeight.Normal)

    /** 日期数字：今天圆点内的日号。 */
    val dayNumber = leafyTextStyle(14.sp, 18.sp, FontWeight.SemiBold)

    /** 节次时间轴。 */
    val axisTime = leafyTextStyle(9.sp, 11.sp, FontWeight.Medium)
}
