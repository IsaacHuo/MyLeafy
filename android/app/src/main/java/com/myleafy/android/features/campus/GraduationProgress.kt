package com.myleafy.android.features.campus

import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.data.local.GradeSummaryEntity
import com.myleafy.android.parsers.ParsedTrainingProgram
import kotlinx.serialization.json.Json
import kotlinx.serialization.decodeFromString

data class GraduationCategory(val name: String, val required: Double, val completed: Double?)
data class GraduationProgress(
    val completed: Double, val required: Double?, val official: Boolean,
    val categories: List<GraduationCategory>, val publicBuckets: Map<String, Double>, val syncedAt: Long?,
) {
    val remaining: Double? get() = required?.let { (it - completed).coerceAtLeast(0.0) }
    companion object {
        private fun category(text: String, fallback: String): String = when {
            listOf("公共选修", "通识选修", "校选", "公选").any(text::contains) -> "公选课"
            listOf("专业选修", "专业任选", "专业限选", "专选").any(text::contains) -> "专选课"
            else -> fallback
        }
        fun calculate(program: ParsedTrainingProgram, grades: List<GradeEntity>, summary: GradeSummaryEntity?): GraduationProgress {
            val requirements = program.creditRequirements
            val total = requirements.filter { it.isTotal && it.isAggregate }.maxOfOrNull { it.credits }
            val nonTotal = requirements.filterNot { it.isTotal }
            val aggregate = nonTotal.filter { it.isAggregate }
            val groups = (if (aggregate.isEmpty()) nonTotal else aggregate).groupBy { category(it.label + it.courseName, it.label) }
            val categories = groups.toSortedMap(compareBy<String> { when(it) { "公选课" -> 0; "专选课" -> 1; else -> 2 } }.thenBy { it }).map { (label, entries) ->
                val aggregates = entries.filter { it.isAggregate }
                val required = if (aggregates.isNotEmpty()) aggregates.maxOf { maxOf(it.credits, it.plannedCredits ?: 0.0) }
                    else entries.sumOf { maxOf(it.credits, it.plannedCredits ?: 0.0) }
                val completed = when {
                    label == "公选课" -> summary?.publicElectiveCredits
                    label == "专选课" -> summary?.professionalMajorElectiveCredits
                    else -> null
                }
                GraduationCategory(label, required, completed)
            }
            val buckets = summary?.publicElectiveBucketsJson?.let { Json.decodeFromString<Map<String, Double>>(it) }.orEmpty()
            return GraduationProgress(summary?.totalCredits ?: GradeAnalytics.calculate(grades).passedCredits, total,
                summary?.totalCredits != null, categories, buckets, summary?.syncedAt)
        }
    }
}
