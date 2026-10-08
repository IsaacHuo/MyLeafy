package com.myleafy.android.testing

import android.app.Application
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.campus.AcademicBarChart
import com.myleafy.android.features.campus.AcademicLineChart
import com.myleafy.android.features.campus.QualityScoreFields
import com.myleafy.android.features.timetable.presentation.TimetableWeekHeader
import com.myleafy.android.ui.components.LeafyDisclosureRow
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class ExperiencePolishScreenshotTest {
    @get:Rule val compose = createComposeRule()

    @Test fun weekHeader393Font130KeepsDateAndClickTarget() {
        var clicks = 0
        compose.setContent { LeafyScreenshotTheme(fontScale = 1.3f) {
            TimetableWeekHeader(4, 4, java.time.LocalDate.of(2026, 9, 28), { clicks++ })
        } }
        compose.onNodeWithText("9.28 – 10.4").assertIsDisplayed().assertTextLayoutFits()
        compose.onNodeWithTag("timetable-week").performClick()
        compose.runOnIdle { assertEquals(1, clicks) }
        compose.onRoot().captureRoboImage()
    }

    @Test
    @Config(sdk = [36], qualifiers = "w412dp-h800dp-xxhdpi", application = Application::class)
    fun weekHeader412Font200KeepsBothLabels() {
        compose.setContent { LeafyScreenshotTheme(fontScale = 2f, darkTheme = true) {
            TimetableWeekHeader(20, 20, java.time.LocalDate.of(2027, 1, 18), {})
        } }
        compose.onNodeWithText("本周 · 第 20 周", useUnmergedTree = true).assertIsDisplayed().assertTextLayoutFits()
        compose.onNodeWithText("1.18 – 1.24").assertIsDisplayed().assertTextLayoutFits()
        compose.onRoot().captureRoboImage()
    }

    @Test fun constrainedLargeWeekHeaderStacksWithoutEllipsis() {
        compose.setContent { LeafyScreenshotTheme(fontScale = 2f) {
            Box(Modifier.fillMaxSize()) {
                TimetableWeekHeader(20, 20, java.time.LocalDate.of(2027, 1, 18), {}, Modifier.width(280.dp))
            }
        } }
        compose.onNodeWithText("本周 · 第 20 周", useUnmergedTree = true).assertTextLayoutFits()
        compose.onNodeWithText("1.18 – 1.24").assertTextLayoutFits()
        val week = compose.onNodeWithTag("timetable-week").fetchSemanticsNode().boundsInRoot
        val range = compose.onNodeWithText("1.18 – 1.24").fetchSemanticsNode().boundsInRoot
        org.junit.Assert.assertTrue("week=$week, date=$range", range.top >= week.bottom)
        compose.onRoot().captureRoboImage()
    }

    @Test fun chartsShowZeroSinglePeriodAndEqualValues() {
        compose.setContent { LeafyScreenshotTheme {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                AcademicLineChart(listOf("2025-2026-1" to 84.0))
                AcademicLineChart(listOf("2025-2026-1" to 84.0, "2025-2026-2" to 84.0))
                AcademicBarChart(listOf("未通过" to 0.0, "60–69" to 2.0, "70–79" to 0.0, "80–89" to 4.0, "90–100" to 3.0))
            }
        } }
        compose.onNodeWithText("2025-2026-1 · 84.00").assertIsDisplayed()
        compose.onNodeWithContentDescription("未通过：0.00", substring = true).assertExists()
        compose.onRoot().captureRoboImage()
    }

    @Test fun largeTextDisclosureKeepsAnAccessibleToggle() {
        compose.setContent { LeafyScreenshotTheme(fontScale = 2f) {
            var expanded by remember { mutableStateOf(false) }
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                LeafyDisclosureRow("专业基础与集中性实践教学安排", expanded, { expanded = !expanded })
                if (expanded) Text("课程明细")
            }
        } }
        compose.onNodeWithText("专业基础与集中性实践教学安排").performClick()
        compose.onNodeWithText("课程明细").assertIsDisplayed()
        compose.onRoot().captureRoboImage()
    }

    @Test fun largeTextQualityFieldsKeepLabelsAndIndependentValues() {
        compose.setContent { LeafyScreenshotTheme(fontScale = 2f) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                QualityScoreFields("90", "官方综素分", {}, "86.5", "官方综合成绩", {})
            }
        } }
        compose.onNodeWithText("官方综素分").assertTextLayoutFits()
        compose.onNodeWithText("官方综合成绩").assertTextLayoutFits()
        compose.onNodeWithText("90").assertIsDisplayed()
        compose.onNodeWithText("86.5").assertIsDisplayed()
        compose.onRoot().captureRoboImage()
    }
}
