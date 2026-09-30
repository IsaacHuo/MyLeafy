package com.myleafy.android.features.timetable

import android.graphics.Bitmap
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.features.timetable.domain.*
import com.myleafy.android.ui.theme.MyLeafyTheme
import java.io.File
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class TimetablePagerTest {
    @get:Rule val compose = createComposeRule()

    @Test fun photoStaysFixedAcrossPagingAndVerticalPullRequestsOnce() {
        val photo = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "pager-photo.png")
        Bitmap.createBitmap(40, 80, Bitmap.Config.ARGB_8888).also { bitmap ->
            val canvas = android.graphics.Canvas(bitmap)
            canvas.drawColor(android.graphics.Color.rgb(213, 227, 211))
            val paint = android.graphics.Paint().apply { color = android.graphics.Color.rgb(72, 119, 83) }
            canvas.drawCircle(5f, 15f, 18f, paint)
            paint.color = android.graphics.Color.rgb(163, 196, 170)
            canvas.drawCircle(35f, 65f, 25f, paint)
            photo.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
        val pages = (1..20).map { week ->
            val range = TimetableWeekRange(week, LocalDate.of(2026, 9, 7).plusWeeks((week - 1).toLong()))
            TimetableWeekPage(week, range, TimetableGridSnapshot(range, emptyList()))
        }
        var selected by mutableStateOf(1)
        var refreshes = 0
        var sync by mutableStateOf<TimetableSyncState>(TimetableSyncState.Idle)
        try {
            compose.setContent {
                MyLeafyTheme {
                    TimetableScreenContent(
                        state = TimetableUiState.Loaded("2026-2027-1", 1, selected, pages[selected - 1].weekRange,
                            emptyList(), emptyList(), emptyList(), pages[selected - 1].grid, 20, pages, true,
                            TimetableBackgroundSettings(enabled = true, kind = "photo", photoPath = photo.absolutePath)),
                        syncState = sync, onRetrySync = { refreshes++; sync = TimetableSyncState.Syncing() },
                        onSelectWeek = { selected = it }, onEmptyCellClick = { _, _ -> }, onItemClick = {}, onConsumeSync = {}, canRefresh = true,
                    )
                }
            }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("timetable-photo").fetchSemanticsNodes().size == 1 }
            val bounds = compose.onNodeWithTag("timetable-photo").fetchSemanticsNode().boundsInRoot
            val axisBounds = compose.onNodeWithTag("timetable-fixed-axis").fetchSemanticsNode().boundsInRoot
            compose.onNodeWithTag("timetable-month").assertTextEquals("9月")
            (1..13).forEach { compose.onNodeWithTag("timetable-axis-end-$it", useUnmergedTree = true).assertIsDisplayed() }
            val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
            val recording = if (InstrumentationRegistry.getArguments().getString("recordReview") == "true") {
                android.os.ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand("mkdir -p /data/local/tmp/myleafy-review")).use { it.readBytes() }
                automation.executeShellCommand("screenrecord --time-limit 12 /data/local/tmp/myleafy-review/timetable.mp4")
            } else null
            repeat(3) {
                compose.onNodeWithTag("timetable-pager").performTouchInput { swipeLeft() }
                compose.waitForIdle()
                compose.onAllNodesWithTag("timetable-photo").assertCountEquals(1)
                assertEquals(bounds, compose.onNodeWithTag("timetable-photo").fetchSemanticsNode().boundsInRoot)
                assertEquals(axisBounds, compose.onNodeWithTag("timetable-fixed-axis").fetchSemanticsNode().boundsInRoot)
                compose.onNodeWithTag("timetable-pager").performTouchInput { swipeRight() }
                compose.waitForIdle()
                assertEquals(1, selected)
            }
            compose.onNodeWithTag("timetable-pager").performTouchInput { swipeDown() }
            compose.waitForIdle()
            assertEquals(1, refreshes)
            compose.onNodeWithText("同步课表").assertIsDisplayed()
            recording?.let { android.os.ParcelFileDescriptor.AutoCloseInputStream(it).use { stream -> stream.readBytes() } }
        } finally { photo.delete() }
    }
}
