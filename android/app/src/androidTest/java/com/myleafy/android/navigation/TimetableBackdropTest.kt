package com.myleafy.android.navigation

import androidx.test.ext.junit.runners.AndroidJUnit4
import android.graphics.Bitmap
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.ui.theme.MyLeafyTheme
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith




@RunWith(AndroidJUnit4::class)


class TimetableBackdropTest {
    @get:Rule val compose = createComposeRule()

    @Test fun photoOwnershipSurvivesRoutesAndRailAndFollowsOnlyTheSelectedPath() {
        val first = File.createTempFile("backdrop-first-", ".png")
        val second = File.createTempFile("backdrop-second-", ".png")
        fun write(file: File, color: Int) {
            val bitmap = Bitmap.createBitmap(20, 40, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(color)
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
        write(first, android.graphics.Color.GREEN)
        write(second, android.graphics.Color.MAGENTA)
        var background by mutableStateOf(TimetableBackgroundSettings(enabled = true, kind = "photo",
            photoPath = first.absolutePath, visibilityPercent = 100, overlayPercent = 0))
        var tab by mutableStateOf(RootTab.TIMETABLE)
        var root by mutableStateOf(true)
        var width by mutableStateOf(360.dp)
        fun photoColor(): Color {
            val pixels = compose.onNodeWithTag("timetable-photo").captureToImage().toPixelMap()
            return pixels[pixels.width / 2, pixels.height / 2]
        }
        try {
            compose.setContent {
                MyLeafyTheme {
                    Box {
                        TimetableNavigationScaffold(background, tab, { tab = it }, Modifier.width(width), root) { Text("内容") }
                    }
                }
            }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("timetable-photo").fetchSemanticsNodes().size == 1 }
            val original = photoColor()
            val phoneWidth = compose.onNodeWithTag("timetable-photo").fetchSemanticsNode().boundsInRoot.width
            assertEquals(Color.Green, original)
            // A second decode would visibly read blue. The root must retain the original bitmap.
            write(first, android.graphics.Color.BLUE)
            compose.onNodeWithTag("root-tab-profile").performClick()
            compose.onNodeWithTag("timetable-photo").assertDoesNotExist()
            compose.onNodeWithTag("root-tab-timetable").performClick()
            assertEquals(original, photoColor())
            compose.runOnIdle { root = false }
            compose.onNodeWithTag("timetable-photo").assertDoesNotExist()
            compose.onNodeWithTag("root-tab-timetable").assertDoesNotExist()
            compose.runOnIdle { root = true; width = 840.dp }
            compose.onNodeWithTag("root-tab-timetable").assertIsSelected()
            org.junit.Assert.assertTrue(compose.onNodeWithTag("timetable-photo").fetchSemanticsNode().boundsInRoot.width > phoneWidth * 2)
            assertEquals(original, photoColor())
            compose.runOnIdle { background = background.copy(photoPath = second.absolutePath) }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("timetable-photo").fetchSemanticsNodes().size == 1 && photoColor() == Color.Magenta }
            compose.runOnIdle { background = background.copy(enabled = false) }
            compose.onNodeWithTag("timetable-background").assertDoesNotExist()
            compose.runOnIdle { width = 360.dp; background = background.copy(enabled = true) }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("timetable-photo").fetchSemanticsNodes().size == 1 }
            assertEquals(Color.Magenta, photoColor())
        } finally { first.delete(); second.delete() }
    }
}
