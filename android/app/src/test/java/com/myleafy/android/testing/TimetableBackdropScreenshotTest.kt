package com.myleafy.android.testing

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.features.timetable.*
import com.myleafy.android.features.timetable.presentation.TimetablePageScaffold
import com.myleafy.android.navigation.TimetableNavigationScaffold
import com.myleafy.android.navigation.RootTab
import com.myleafy.android.ui.components.LeafyActionIconButton
import java.io.File
import java.time.LocalDateTime
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class TimetableBackdropScreenshotTest {
    @get:Rule val compose = createComposeRule()

    @Test fun defaultLight() = render(TimetableBackgroundSettings())
    @Test fun defaultDark() = render(TimetableBackgroundSettings(), dark = true)
    @Test fun solidLight() = render(TimetableBackgroundSettings(enabled = true, colorHex = "#A3C1B0"))
    @Test fun solidDark() = render(TimetableBackgroundSettings(enabled = true, colorHex = "#375057"), dark = true)
    @Test fun brightPhotoLight() = photo(false)
    @Test fun darkPhotoDark() = photo(true, dark = true)
    @Test fun darkestPhotoLightNoOverlay() = photo(true, pressure = true)
    @Test fun brightestPhotoDarkNoOverlay() = photo(false, dark = true, pressure = true)
    @Test @Config(qualifiers = "w393dp-h640dp-xxhdpi")
    fun shortWeekdaysPhotoFont200() = photo(false, scale = 2f, weekends = false)
    @Test @Config(qualifiers = "w412dp-h800dp-xxhdpi")
    fun sevenDaysDarkPhotoFont200() = photo(true, dark = true, scale = 2f)
    @Test @Config(qualifiers = "w600dp-h900dp-xxhdpi")
    fun solidRail600() = render(TimetableBackgroundSettings(enabled = true, colorHex = "#A3C1B0"))
    @Test @Config(qualifiers = "w840dp-h900dp-xxhdpi")
    fun photoRail840Dark() = photo(true, dark = true)
    @Test @Config(qualifiers = "w840dp-h393dp-xxhdpi")
    fun landscapePhotoFit() = photo(false, fit = true)

    private fun photo(darkPhoto: Boolean, dark: Boolean = false, pressure: Boolean = false, scale: Float = 1f, weekends: Boolean = true, fit: Boolean = false) {
        val file = File.createTempFile("timetable-shell-", ".png")
        try {
            Bitmap.createBitmap(120, 240, Bitmap.Config.ARGB_8888).also { bitmap ->
                val canvas = Canvas(bitmap)
                canvas.drawColor(if (darkPhoto) android.graphics.Color.rgb(9, 17, 25) else android.graphics.Color.rgb(250, 245, 232))
                val paint = Paint().apply { color = if (darkPhoto) android.graphics.Color.rgb(43, 80, 85) else android.graphics.Color.rgb(124, 175, 141) }
                canvas.drawCircle(20f, 100f, 65f, paint)
                canvas.drawRect(72f, 160f, 120f, 240f, paint)
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
            }
            render(TimetableBackgroundSettings(enabled = true, kind = "photo", photoPath = file.absolutePath,
                visibilityPercent = if (pressure) 100 else 55, overlayPercent = if (pressure) 0 else 30, contentScale = if (fit) "fit" else "crop"), dark, scale, weekends)
        } finally { file.delete() }
    }

    private fun render(background: TimetableBackgroundSettings, dark: Boolean = false, scale: Float = 1f, weekends: Boolean = true) {
        val snapshot = weekOneSnapshot().let { it.copy(items = it.items + gridItem("late", "晚间研讨", "学研 204", 2, 13, 1)) }
        val pages = listOf(TimetableWeekPage(1, snapshot.weekRange, snapshot))
        val state = TimetableUiState.Loaded("2026-2027-1", 1, 1, snapshot.weekRange, emptyList(), emptyList(), emptyList(), snapshot, 1, pages, weekends, background)
        compose.setContent {
            LeafyScreenshotTheme(darkTheme = dark, fontScale = scale) {
                TimetableNavigationScaffold(background, RootTab.TIMETABLE, {}) {
                    TimetablePageScaffold(
                        background = background,
                        titleContent = { Text("课表", style = androidx.compose.material3.MaterialTheme.typography.titleLarge) },
                        actions = {
                            LeafyActionIconButton(onClick = {}) { Icon(Icons.Filled.Add, "添加日程") }
                            LeafyActionIconButton(onClick = {}) { Icon(Icons.Filled.MoreVert, "课表操作") }
                        },
                    ) { padding ->
                        TimetableScreenContent(state, TimetableSyncState.Idle, {}, {}, { _, _ -> }, {}, {},
                            modifier = Modifier.padding(padding), now = LocalDateTime.of(2026, 9, 9, 10, 27).atZone(ScreenshotData.campusZone))
                    }
                }
            }
        }
        if (background.enabled && background.kind == "photo") compose.waitUntil(5_000) {
            compose.onAllNodesWithTag("timetable-photo").fetchSemanticsNodes().size == 1
        }
        compose.onNodeWithTag("root-tab-timetable").assertIsSelected()
        compose.onNodeWithContentDescription("添加日程").assertIsDisplayed()
        compose.onNodeWithContentDescription("课表操作").assertIsDisplayed()
        compose.onNodeWithTag("timetable-axis-period-13", useUnmergedTree = true).assertIsDisplayed()
        compose.onRoot().captureRoboImage()
    }
}
