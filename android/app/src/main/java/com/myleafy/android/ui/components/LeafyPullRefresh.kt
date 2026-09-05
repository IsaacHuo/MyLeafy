package com.myleafy.android.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Velocity
import com.myleafy.android.ui.theme.LeafyGesture
import kotlin.math.max

/** 使用稳定 NestedScroll API 的轻量下拉刷新状态，不依赖实验性 Material API。 */
@Stable
class LeafyPullRefreshState internal constructor(
    internal val thresholdPx: Float,
    private val onRefresh: () -> Unit,
) {
    internal var dragDistance by mutableFloatStateOf(0f)
    internal var enabled: Boolean = true
    val progress: Float get() = (dragDistance / thresholdPx).coerceIn(0f, 1f)

    private fun release() {
        if (enabled && dragDistance >= thresholdPx) onRefresh()
        dragDistance = 0f
    }

    internal val connection = object : NestedScrollConnection {
        override fun onPostScroll(
            consumed: Offset,
            available: Offset,
            source: NestedScrollSource,
        ): Offset {
            if (!enabled || source != NestedScrollSource.UserInput || available.y <= 0f) return Offset.Zero
            dragDistance = (dragDistance + available.y * 0.55f).coerceAtMost(thresholdPx * 1.35f)
            return Offset(0f, available.y)
        }

        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            if (source != NestedScrollSource.UserInput || available.y >= 0f || dragDistance <= 0f) {
                return Offset.Zero
            }
            val consumedY = max(available.y, -dragDistance)
            dragDistance += consumedY
            return Offset(0f, consumedY)
        }

        override suspend fun onPreFling(available: Velocity): Velocity {
            release()
            return Velocity.Zero
        }
    }
}

@Composable
fun rememberLeafyPullRefreshState(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
): LeafyPullRefreshState {
    val callback by rememberUpdatedState(onRefresh)
    val thresholdPx = with(LocalDensity.current) { LeafyGesture.pullRefreshThreshold.toPx() }
    val state = remember(thresholdPx) { LeafyPullRefreshState(thresholdPx) { callback() } }
    LaunchedEffect(isRefreshing) {
        if (isRefreshing) state.dragDistance = 0f
    }
    return state
}

fun Modifier.leafyPullRefresh(
    state: LeafyPullRefreshState,
    enabled: Boolean,
): Modifier {
    state.enabled = enabled
    return nestedScroll(state.connection)
}
