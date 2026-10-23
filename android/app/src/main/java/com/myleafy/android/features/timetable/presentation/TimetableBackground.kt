package com.myleafy.android.features.timetable.presentation

import android.graphics.BitmapFactory
import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.ui.theme.LeafyTimetableBackgroundFallback
import com.myleafy.android.ui.theme.leafySurfaces
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** One full-window canvas. Edge protection fades into the photo without separate bars. */
@Composable
internal fun TimetablePageBackdrop(
    settings: TimetableBackgroundSettings,
    visible: Boolean,
    modifier: Modifier = Modifier,
) {
    Box(modifier) {
        TimetableBackground(settings, Modifier.matchParentSize(), visible)
        if (settings.enabled && visible) {
            val density = LocalDensity.current
            val page = MaterialTheme.leafySurfaces.page
            val protection = page.copy(alpha = if (page.luminance() < 0.5f) 0.86f else 0.82f)
            val topPlateau = WindowInsets.statusBars.getTop(density) + with(density) { (120.dp * fontScale).toPx() }
            val top = topPlateau + with(density) { 64.dp.toPx() }
            val bottom = WindowInsets.navigationBars.getBottom(density) + with(density) { (80.dp * fontScale).toPx() }
            val axis = with(density) { timetableAxisWidth().toPx() }
            Canvas(Modifier.matchParentSize()) {
                drawRect(Brush.verticalGradient(0f to protection, topPlateau / top to protection, 1f to Color.Transparent, endY = top), size = Size(size.width, top.coerceAtMost(size.height)))
                val start = (size.height - bottom).coerceAtLeast(0f)
                drawRect(Brush.verticalGradient(listOf(Color.Transparent, protection), startY = start, endY = size.height),
                    topLeft = Offset(0f, start), size = Size(size.width, size.height - start))
                val plateau = axis + if (size.width >= 600.dp.toPx()) 96.dp.toPx() else 8.dp.toPx()
                val edge = plateau + 24.dp.toPx()
                val axisProtection = page.copy(alpha = if (page.luminance() < 0.5f) 0.74f else 0.70f)
                drawRect(Brush.horizontalGradient(0f to axisProtection, plateau / edge to axisProtection, 1f to Color.Transparent, endX = edge), size = Size(edge, size.height))
            }
        }
    }
}

/** A continuous soft edge behind the whole axis; never paints individual period rows. */
@Composable
internal fun Modifier.timetableAxisBackdrop(enabled: Boolean, axisWidth: androidx.compose.ui.unit.Dp): Modifier {
    if (!enabled || axisWidth.value <= 0f) return this
    val page = MaterialTheme.leafySurfaces.page
    val protection = page.copy(alpha = if (page.luminance() < 0.5f) 0.66f else 0.58f)
    return drawBehind {
        val edge = axisWidth.toPx() + 24.dp.toPx()
        drawRect(Brush.horizontalGradient(0f to protection, (axisWidth.toPx() / edge) to protection, 1f to Color.Transparent, endX = edge),
            size = Size(edge, size.height))
    }
}

@Composable
fun TimetableBackground(
    settings: TimetableBackgroundSettings,
    modifier: Modifier = Modifier,
    visible: Boolean = true,
) {
    val selectedPath = if (!settings.enabled || settings.kind == "color") null
    else if (Build.VERSION.SDK_INT < 31 && settings.blurRadius > 0) settings.blurredPhotoPath ?: settings.photoPath
    else settings.photoPath
    // Root ownership survives tab/route changes. Only the selected file restarts decoding.
    val bitmap by key(selectedPath) {
        produceState<android.graphics.Bitmap?>(null) {
            value = withContext(Dispatchers.IO) { selectedPath?.let(::decodeTimetableBackground) }
        }
    }
    if (!settings.enabled || !visible) return
    val pageColor = MaterialTheme.leafySurfaces.page
    Box(modifier = modifier.testTag("timetable-background")) {
        if (settings.kind == "color") {
            Box(
                modifier = Modifier.fillMaxSize().background(
                    parseBackgroundColor(settings.colorHex).copy(alpha = settings.visibilityPercent / 100f),
                ),
            )
        } else {
            bitmap?.let { image ->
                Image(
                    bitmap = image.asImageBitmap(),
                    contentDescription = null,
                    contentScale = if (settings.contentScale == "fit") ContentScale.Fit else ContentScale.Crop,
                    alpha = settings.visibilityPercent / 100f,
                    modifier = Modifier.fillMaxSize().testTag("timetable-photo").then(
                        if (Build.VERSION.SDK_INT >= 31 && settings.blurRadius > 0) {
                            Modifier.graphicsLayer {
                                renderEffect = RenderEffect.createBlurEffect(
                                    settings.blurRadius.toFloat(),
                                    settings.blurRadius.toFloat(),
                                    Shader.TileMode.CLAMP,
                                ).asComposeRenderEffect()
                            }
                        } else {
                            Modifier
                        },
                    ),
                )
            }
        }
        if (settings.overlayPercent > 0) {
            Box(
                modifier = Modifier.fillMaxSize().background(
                    pageColor.copy(alpha = settings.overlayPercent / 100f),
                ),
            )
        }
    }
}

private fun decodeTimetableBackground(path: String, maxSide: Int = 1_920): android.graphics.Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > maxSide * 2) sample *= 2
    return BitmapFactory.decodeFile(
        path,
        BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = android.graphics.Bitmap.Config.ARGB_8888
        },
    )
}

private fun parseBackgroundColor(value: String): Color = runCatching {
    Color(android.graphics.Color.parseColor(value))
}.getOrDefault(LeafyTimetableBackgroundFallback)
