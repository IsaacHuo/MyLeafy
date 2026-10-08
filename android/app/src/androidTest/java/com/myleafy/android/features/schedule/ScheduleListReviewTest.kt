package com.myleafy.android.features.schedule

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import com.myleafy.android.features.schedule.notifications.ScheduleReportsUiState
import com.myleafy.android.ui.theme.MyLeafyTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ScheduleListReviewTest {
    @get:Rule val compose = createComposeRule()

    @Test fun lastMemoRemainsReadableAndClickableAboveTheCreateButtonAtLargeFont() {
        com.myleafy.android.testing.resetRenderReview()
        val memos = (0..199).map { index -> ScheduleMemoEntity("review", "memo-$index",
            "长正文说明与 English mixed text。".repeat(20), "quickMemo", "记录 $index", "", 1_790_000_000_000L,
            1_790_000_000_000L, null, null, null, null) }
        var opened: String? = null
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MyLeafyTheme {
                    ScheduleContent(ScheduleSection.MEMOS, memos, emptyList(), {}, { opened = it.id }, {}, {}, {},
                        ScheduleReportsUiState(), false, { _, _ -> }, { _, _, _ -> })
                }
            }
        }
        compose.onNode(hasScrollAction()).performScrollToIndex(199)
        compose.onNodeWithText("记录 199").assertIsDisplayed().performClick()
        assertEquals("memo-199", opened)
        val last = compose.onNodeWithText("记录 199").fetchSemanticsNode().boundsInRoot
        val create = compose.onNodeWithTag("schedule-create").fetchSemanticsNode().boundsInRoot
        assertTrue("last=$last, create=$create", last.bottom < create.top)
        compose.onNodeWithTag("schedule-create").assertIsDisplayed()
        com.myleafy.android.testing.captureRenderReview("memo-list")
    }
}
