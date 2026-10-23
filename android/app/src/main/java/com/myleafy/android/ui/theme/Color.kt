package com.myleafy.android.ui.theme

import androidx.compose.ui.graphics.Color

// 品牌色：默认“鼠尾草绿”（与 iOS AppTheme.green 一致）
// base RGB(157,193,131) / emphasis RGB(95,127,78) / soft RGB(236,244,231) / textOnAccent RGB(32,53,31)
val LeafyGreen = Color(0xFF9DC183)
val LeafyGreenEmphasis = Color(0xFF5F7F4E)
val LeafyGreenSoft = Color(0xFFECF4E7)
val LeafyGreenTextOnAccent = Color(0xFF20351F)

// 深色模式下的品牌色微调（保持可读性）
val LeafyGreenDark = Color(0xFFB6D49C)
val LeafyGreenEmphasisDark = Color(0xFF8FB27A)

val LeafyLavender = Color(0xFF756A86)
val LeafyWarning = Color(0xFF8A6418)
val LeafyDanger = Color(0xFFBA1A1A)

// 课表自定义纯色背景解析失败时使用的稳定默认色
val LeafyTimetableBackgroundFallback = Color(0xFFDDE9DF)

/**
 * 课程色不是 7 个互不相关的色相，而是同一品牌基色按白度/暗度递进。
 * 与 iOS `AppTheme.generatedCourseCards` 的生成方式一致：
 * 同一课表里保持统一色温，靠位置和文字区分课程。
 */
val LeafyCoursePaletteLight = listOf(
    Color(0xFFD8E6CD),
    Color(0xFFD1E2C5),
    Color(0xFFCADEBC),
    Color(0xFFC3D9B3),
    Color(0xFFBCD5AB),
    Color(0xFFB6D1A2),
    Color(0xFFAFCC99),
)

val LeafyCoursePaletteDark = listOf(
    Color(0xFF36412F),
    Color(0xFF3D4A35),
    Color(0xFF44523B),
    Color(0xFF4B5B40),
    Color(0xFF526446),
    Color(0xFF596C4C),
    Color(0xFF607551),
)
