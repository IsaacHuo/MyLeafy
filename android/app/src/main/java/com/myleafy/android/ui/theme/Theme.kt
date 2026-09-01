package com.myleafy.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
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
    tertiary = LeafyLavender,
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFEDE5F3),
    onTertiaryContainer = Color(0xFF2A2430),
    background = Color(0xFFF7F8F5),
    onBackground = Color(0xFF1B1C1A),
    surface = Color.White,
    onSurface = Color(0xFF1B1C1A),
    surfaceVariant = Color(0xFFE5E9E1),
    onSurfaceVariant = Color(0xFF454841),
    surfaceTint = LeafyGreen,
    inverseSurface = Color(0xFF30322E),
    inverseOnSurface = Color(0xFFF1F2ED),
    inversePrimary = LeafyGreenDark,
    outline = Color(0xFF74786F),
    outlineVariant = Color(0xFFDDE1D8),
    scrim = Color.Black,
    error = LeafyDanger,
    onError = Color.White,
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    surfaceBright = Color.White,
    surfaceDim = Color(0xFFD9DAD5),
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = Color(0xFFF3F5F0),
    surfaceContainer = Color(0xFFEDEFEB),
    surfaceContainerHigh = Color(0xFFE7E9E4),
    surfaceContainerHighest = Color(0xFFE1E3DE),
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
    tertiary = Color(0xFFD1C0DE),
    onTertiary = Color(0xFF382D43),
    tertiaryContainer = Color(0xFF4F435A),
    onTertiaryContainer = Color(0xFFEEDDFB),
    background = Color(0xFF121310),
    onBackground = Color(0xFFE3E4DF),
    surface = Color(0xFF1A1C18),
    onSurface = Color(0xFFE3E4DF),
    surfaceVariant = Color(0xFF44483F),
    onSurfaceVariant = Color(0xFFC4C8BD),
    surfaceTint = LeafyGreenDark,
    inverseSurface = Color(0xFFE3E4DF),
    inverseOnSurface = Color(0xFF30322E),
    inversePrimary = LeafyGreenEmphasis,
    outline = Color(0xFF8E9288),
    outlineVariant = Color(0xFF44483F),
    scrim = Color.Black,
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    surfaceBright = Color(0xFF383A35),
    surfaceDim = Color(0xFF121310),
    surfaceContainerLowest = Color(0xFF0D0F0C),
    surfaceContainerLow = Color(0xFF1A1C18),
    surfaceContainer = Color(0xFF1E201C),
    surfaceContainerHigh = Color(0xFF282A26),
    surfaceContainerHighest = Color(0xFF333531),
)

private val LightSurfaces = LeafySurfaceColors(
    page = Color(0xFFF7F8F5),
    grouped = Color(0xFFF1F4EE),
    content = Color.White,
    elevated = Color(0xFFFBFCF9),
    modal = Color.White,
    accentSoft = LeafyGreenSoft,
)

private val DarkSurfaces = LeafySurfaceColors(
    page = Color(0xFF121310),
    grouped = Color(0xFF171915),
    content = Color(0xFF1E201C),
    elevated = Color(0xFF282A26),
    modal = Color(0xFF20221E),
    accentSoft = Color(0xFF2D4A22),
)

private val LocalLeafySurfaces = staticCompositionLocalOf { LightSurfaces }
private val LocalLeafyCourseColors = staticCompositionLocalOf {
    LeafyCourseColors(LeafyCoursePaletteLight, LeafyGreenTextOnAccent)
}

val MaterialTheme.leafySurfaces: LeafySurfaceColors
    @Composable
    @ReadOnlyComposable
    get() = LocalLeafySurfaces.current

val MaterialTheme.leafyCourseColors: LeafyCourseColors
    @Composable
    @ReadOnlyComposable
    get() = LocalLeafyCourseColors.current

@Composable
fun MyLeafyTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val surfaces = if (darkTheme) DarkSurfaces else LightSurfaces
    val courseColors = if (darkTheme) {
        LeafyCourseColors(LeafyCoursePaletteDark, Color(0xFFF1F4ED))
    } else {
        LeafyCourseColors(LeafyCoursePaletteLight, LeafyGreenTextOnAccent)
    }
    CompositionLocalProvider(
        LocalLeafySurfaces provides surfaces,
        LocalLeafyCourseColors provides courseColors,
    ) {
        MaterialTheme(
            colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme,
            typography = MyLeafyTypography,
            shapes = MyLeafyShapes,
            content = content,
        )
    }
}
