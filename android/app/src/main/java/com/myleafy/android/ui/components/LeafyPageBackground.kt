package com.myleafy.android.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import com.myleafy.android.ui.theme.leafySurfaces

/**
 * 根页面的极淡主题渐变。iOS 用 systemGroupedBackground + accent 8% 做同样的事；
 * 没有它，大面积留白会显得平，卡片只能靠白/灰硬切。
 */
@Composable
fun LeafyPageBackground(modifier: Modifier = Modifier) {
    val page = MaterialTheme.leafySurfaces.page
    val accent = MaterialTheme.colorScheme.primary
    val tintAlpha = if (page.luminance() < 0.5f) 0.05f else 0.08f
    Canvas(modifier) {
        drawRect(page)
        if (size.width <= 0f || size.height <= 0f) return@Canvas
        drawRect(
            brush = Brush.linearGradient(
                colors = listOf(
                    Color.Transparent,
                    accent.copy(alpha = tintAlpha),
                    Color.Transparent,
                ),
                start = Offset.Zero,
                end = Offset(size.width, size.height),
            ),
        )
    }
}
