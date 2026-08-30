package com.myleafy.android.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/** Stable brand corner hierarchy shared by cards, controls, dialogs and sheets. */
object LeafyCorners {
    val compact = 12.dp
    val standard = 16.dp
    val prominent = 24.dp
}

val MyLeafyShapes = Shapes(
    extraSmall = RoundedCornerShape(LeafyCorners.compact),
    small = RoundedCornerShape(LeafyCorners.compact),
    medium = RoundedCornerShape(LeafyCorners.standard),
    large = RoundedCornerShape(LeafyCorners.prominent),
    extraLarge = RoundedCornerShape(LeafyCorners.prominent),
)
