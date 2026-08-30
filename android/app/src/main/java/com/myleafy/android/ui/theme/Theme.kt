package com.myleafy.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColorScheme = lightColorScheme(
    primary = LeafyGreen,
    onPrimary = LeafyGreenTextOnAccent,
    primaryContainer = LeafyGreenSoft,
    onPrimaryContainer = LeafyGreenTextOnAccent,
    secondary = LeafyGreenEmphasis,
    onSecondary = Color.White,
    secondaryContainer = LeafyGreenSoft,
    onSecondaryContainer = LeafyGreenTextOnAccent,
    background = Color(0xFFF7F8F5),
    onBackground = Color(0xFF1B1C1A),
    surface = Color.White,
    onSurface = Color(0xFF1B1C1A),
)

private val DarkColorScheme = darkColorScheme(
    primary = LeafyGreenDark,
    onPrimary = Color(0xFF17330F),
    primaryContainer = Color(0xFF2D4A22),
    onPrimaryContainer = LeafyGreenSoft,
    secondary = LeafyGreenEmphasisDark,
    onSecondary = Color(0xFF0E1E08),
    secondaryContainer = Color(0xFF2D4A22),
    onSecondaryContainer = LeafyGreenSoft,
    background = Color(0xFF121310),
    onBackground = Color(0xFFE3E4DF),
    surface = Color(0xFF1A1C18),
    onSurface = Color(0xFFE3E4DF),
)

@Composable
fun MyLeafyTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme,
        typography = MyLeafyTypography,
        shapes = MyLeafyShapes,
        content = content,
    )
}
