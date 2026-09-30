package com.myleafy.android.features.campus

import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.data.local.GradeSummaryEntity
import org.junit.Assert.*
import org.junit.Test

class GradeAnalyticsTest {
    private fun grade(id: String, score: String, credit: String = "3", code: String? = id, term: String = "2026-2027-1", name: String = "课程") =
        GradeEntity("school", id, term, name, credit, score, "必修", code)

    @Test fun `retakes choose highest passing result by code while distinct codes stay separate`() {
        val result = GradeAnalytics.calculate(listOf(grade("old", "58", code = "A", term = "2025-2026-2"),
            grade("new", "78", code = "A"), grade("later", "66", code = "A"), grade("different", "90", code = "B")))
        assertEquals(2, result.effectiveCourseCount)
        assertEquals(3, result.courses.single { it.record.courseCode == "A" }.attemptCount)
        assertEquals(84.0, result.weightedAverage!!, 0.00001)
        assertNull(result.officialGpa)
    }

    @Test fun `missing codes stay within term and text grades affect credits but never average`() {
        val result = GradeAnalytics.calculate(listOf(grade("one", "80", code = null),
            grade("two", "90", code = null, term = "2025-2026-2"), grade("text", "合格", "2"),
            grade("fail", "不合格", "1"), grade("zero", "100", "0")))
        assertEquals(5, result.effectiveCourseCount)
        assertEquals(8.0, result.passedCredits, 0.00001)
        assertEquals(85.0, result.weightedAverage!!, 0.00001)
        assertEquals(90.0, result.median!!, 0.00001)
        assertEquals(1, result.riskCourseCount)
        assertEquals(3, result.distribution.sumOf { it.count })
    }

    @Test fun `invalid records are excluded and empty or zero credits have no fabricated average`() {
        val result = GradeAnalytics.calculate(listOf(grade("nan", "NaN"), grade("over", "101"),
            grade("negative", "80", "-1"), grade("unknown", "缓考")))
        assertEquals(0, result.effectiveCourseCount)
        assertNull(result.passRate)
        assertNull(result.weightedAverage)
        assertNull(GradeAnalytics.calculate(listOf(grade("zero", "90", "0"))).weightedAverage)
    }

    @Test fun `official values override display only leaving local statistics independent`() {
        val result = GradeAnalytics.calculate(listOf(grade("a", "80")),
            GradeSummaryEntity(scopeKey = "school", officialGpa = 3.8, officialWeightedAverage = 89.0, officialCreditPoint = null))
        assertEquals(3.8, result.officialGpa!!, 0.00001)
        assertEquals(89.0, result.displayWeightedAverage!!, 0.00001)
        assertEquals(80.0, result.weightedAverage!!, 0.00001)
    }
}
