package com.myleafy.android.features.campus

import android.graphics.Bitmap
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.data.local.*
import com.myleafy.android.features.auth.*
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.theme.MyLeafyTheme
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** Production composables on the emulator, using local test fixtures only. */
class CoreVisualReviewTest {
    @get:Rule val compose = createComposeRule()
    private data class Variant(val page: String, val width: Int, val font: Float, val dark: Boolean)
    private val grades = listOf(
        GradeEntity("review", "a", "2025-2026-2", "森林生态学", "3.5", "92", "必修", "A"),
        GradeEntity("review", "b", "2025-2026-2", "数据结构与算法设计", "4", "86", "必修", "B"),
        GradeEntity("review", "c", "2025-2026-2", "高等数学", "5", "58", "必修", "C"),
        GradeEntity("review", "d", "2025-2026-1", "体育", "1", "优秀", "必修", "D"),
        GradeEntity("review", "e", "2025-2026-1", "大学英语", "3", "88", "必修", "E"),
    )
    private val state = CampusUiState.Loaded(grades.map { it.term }.distinct(), grades,
        listOf(GradeRankingEntity("review", "ranking", "2025-2026-2", "专业", 12, 96, "学校官方")),
        GradeSummaryEntity("review", officialGpa = 3.62, officialWeightedAverage = 84.2, officialCreditPoint = null), emptyList())

    @Test fun corePagesRemainReadableAndActionsReachableAcrossSizes() {
        var variant by mutableStateOf(Variant("login", 360, 1f, false))
        var submitted = 0
        var analysisOpened = 0
        var gradesOpened = 0
        compose.setContent {
            val physicalWidth = InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.widthPixels
            CompositionLocalProvider(LocalDensity provides Density(physicalWidth / variant.width.toFloat(), variant.font)) {
                MyLeafyTheme(darkTheme = variant.dark) {
                    key(variant) {
                        Surface(Modifier.fillMaxWidth().heightIn(max = 900.dp)) {
                            when (variant.page) {
                                "login" -> LoginContent(LoginUiState(), "20260101", "test-password", "ABCD", {}, {}, {}, { submitted++ }, {}, {},
                                    entryHeader = { EntryHeader(true, false) {} })
                                "grades" -> LeafySecondaryScaffold("成绩查询", {}) { GradesContent(state, it) { analysisOpened++ } }
                                "analysis" -> LeafySecondaryScaffold("成绩分析", {}) { GradeAnalysisContent(state, it) }
                                else -> LeafySecondaryScaffold("校园", {}) {
                                    CampusDashboard(CampusSyncState.Error("同步失败，请重试"), CampusID.bjfu, {}, {},
                                        { gradesOpened++ }, {}, {}, {}, it)
                                }
                            }
                        }
                    }
                }
            }
        }
        val variants = listOf(
            Variant("login", 360, 1f, false), Variant("login", 360, 2f, true),
            Variant("grades", 360, 1f, false), Variant("grades", 360, 2f, true),
            Variant("analysis", 360, 1f, false), Variant("analysis", 600, 1.3f, false),
            Variant("analysis", 840, 2f, true), Variant("campus", 360, 1.3f, false),
            Variant("campus", 600, 2f, true), Variant("campus", 840, 1f, false),
        )
        variants.forEach { next ->
            compose.runOnIdle { variant = next }
            compose.waitForIdle()
            capture("${next.page}-${next.width}-${next.font}-${if (next.dark) "dark" else "light"}")
            when (next.page) {
                "login" -> compose.onNode(hasScrollAction()).performScrollToNode(hasText("登录")).also {
                    compose.onNodeWithText("登录").assertIsDisplayed().assertIsEnabled().performClick()
                }
                "grades" -> {
                    compose.onNodeWithText("查看分析").assertIsDisplayed().performClick()
                    compose.onNode(hasScrollAction()).performScrollToNode(hasText("大学英语"))
                    compose.onNodeWithText("大学英语").assertIsDisplayed()
                }
                "analysis" -> {
                    compose.onNode(hasScrollAction()).performScrollToNode(hasText("统计口径"))
                    compose.onNodeWithText("统计口径").assertIsDisplayed()
                }
                "campus" -> compose.onNodeWithText("成绩查询").assertIsDisplayed().performClick()
            }
        }
        compose.runOnIdle { assertEquals(2, submitted); assertEquals(2, analysisOpened); assertEquals(3, gradesOpened) }
    }

    private fun capture(name: String) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.getExternalFilesDir(null), "review-latest").apply { mkdirs() }
        compose.onRoot().captureToImage().asAndroidBitmap().let { bitmap ->
            val file = File(directory, "$name.png")
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            listOf("mkdir -p /data/local/tmp/myleafy-review", "cp ${file.absolutePath} /data/local/tmp/myleafy-review/$name.png").forEach { command ->
                android.os.ParcelFileDescriptor.AutoCloseInputStream(
                    InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
                ).use { assertEquals("Screenshot export", "", it.readBytes().toString(Charsets.UTF_8)) }
            }
        }
    }
}
