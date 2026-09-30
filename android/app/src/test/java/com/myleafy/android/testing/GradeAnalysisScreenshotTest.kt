package com.myleafy.android.testing

import android.app.Application
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.campus.*
import com.myleafy.android.ui.components.LeafySecondaryScaffold
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
class GradeAnalysisScreenshotTest {
    @get:Rule val compose = createComposeRule()
    private val state = CampusUiState.Loaded(listOf("2025-2026-2", "2025-2026-1"),
        listOf(gradeEntity("a", "森林生态学"), gradeEntity("b", "高等数学", "5", "58"),
            gradeEntity("c", "大学英语", "3", "88", "2025-2026-1")),
        listOf(rankingEntity()), gradeSummary(), emptyList())

    @Test fun gradesGrouped360() {
        compose.setContent { LeafyScreenshotTheme { LeafySecondaryScaffold("成绩查询", {}) { GradesContent(state, it) {} } } }
        compose.onNodeWithText("高等数学").assertIsDisplayed()
        compose.onRoot().captureRoboImage()
    }

    @Test
    @Config(sdk = [36], qualifiers = "w600dp-h900dp-xxhdpi", application = Application::class)
    fun analysis600Font130() {
        compose.setContent { LeafyScreenshotTheme(fontScale = 1.3f) { LeafySecondaryScaffold("成绩分析", {}) { GradeAnalysisContent(state, it) } } }
        compose.onRoot().captureRoboImage()
    }

    @Test
    @Config(sdk = [36], qualifiers = "w840dp-h900dp-xxhdpi", application = Application::class)
    fun analysis840DarkFont200() {
        compose.setContent { LeafyScreenshotTheme(darkTheme = true, fontScale = 2f) { LeafySecondaryScaffold("成绩分析", {}) { GradeAnalysisContent(state, it) } } }
        compose.onRoot().captureRoboImage()
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("统计口径"))
        compose.onNodeWithText("统计口径").assertIsDisplayed()
    }
}
