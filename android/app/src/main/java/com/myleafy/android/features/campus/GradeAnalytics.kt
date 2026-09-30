package com.myleafy.android.features.campus

import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.data.local.GradeSummaryEntity
import kotlin.math.abs
import kotlin.math.sqrt

/** Mirrors iOS GradeAnalytics / EffectiveGradeCourseResolver. No inferred GPA or letter-score conversion. */
data class GradeAnalytics(
    val courses: List<Course>,
    val rawRecordCount: Int,
    val officialGpa: Double?,
    val officialWeightedAverage: Double?,
    val officialCreditPoint: Double?,
) {
    data class Course(val record: GradeEntity, val credit: Double, val score: Double?, val isPassed: Boolean, val attemptCount: Int) {
        val category = record.type.ifBlank { "未分类" }
    }
    data class Group(val name: String, val courses: List<Course>) {
        val credits = courses.sumOf { it.credit }
        val average = average(courses)
    }
    data class Bucket(val range: String, val count: Int, val credits: Double)

    val effectiveCourseCount = courses.size
    val totalCredits = courses.sumOf { it.credit }
    val passedCredits = courses.filter { it.isPassed }.sumOf { it.credit }
    val riskCourseCount = courses.count { !it.isPassed }
    val passRate = courses.takeIf { it.isNotEmpty() }?.let { it.count { course -> course.isPassed }.toDouble() / it.size }
    val weightedAverage = average(courses)
    val displayWeightedAverage = officialWeightedAverage ?: weightedAverage
    val weightedAverageSource = if (officialWeightedAverage == null) "MyLeafy 估算" else "学校官方"
    private val scores = courses.mapNotNull { it.score }.sorted()
    val scoredCourseCount = scores.size
    val median = scores.takeIf { it.isNotEmpty() }?.let { (it[(it.size - 1) / 2] + it[it.size / 2]) / 2 }
    val standardDeviation = scores.takeIf { it.size > 1 }?.let { values ->
        val mean = values.average()
        sqrt(values.sumOf { (it - mean) * (it - mean) } / values.size)
    }
    val terms = courses.groupBy { it.record.term }.toSortedMap(reverseOrder()).map { (name, values) -> Group(name, values.sortedWith(scoreDescending)) }
    val categories = courses.groupBy { it.category }.toSortedMap().map { (name, values) -> Group(name, values) }
    val distribution = listOf("90+" to 90.0, "80-89" to 80.0, "70-79" to 70.0, "60-69" to 60.0, "<60" to 0.0).map { (range, lower) ->
        val upper = if (lower == 0.0) 60.0 else if (lower == 90.0) 101.0 else lower + 10
        val values = courses.filter { it.score != null && it.score >= lower && it.score < upper }
        Bucket(range, values.size, values.sumOf { it.credit })
    }
    val lowScoreFirst = courses.sortedWith(compareBy<Course> { it.isPassed }
        .thenBy { it.score == null }.thenBy { it.score }.thenByDescending { it.record.term }.thenBy { it.record.courseName })
    val highImpact = courses.sortedWith(compareBy<Course> { it.score == null }
        .thenByDescending { impact(it) ?: 0.0 }.then(scoreDescending))
    fun impact(course: Course): Double? = course.score?.let { abs(it - (weightedAverage ?: it)) * course.credit }

    companion object {
        private val scoreDescending = compareBy<Course> { it.score == null }.thenByDescending { it.score }
            .thenBy { it.isPassed }.thenByDescending { it.record.term }.thenBy { it.record.courseName }
        private val failing = listOf("不及格", "不合格", "未通过", "不通过")
        private val passing = listOf("优秀", "良好", "中等", "及格", "合格", "通过")
        private fun average(courses: List<Course>): Double? {
            val numeric = courses.filter { it.score != null }
            val credits = numeric.sumOf { it.credit }
            return if (credits > 0) numeric.sumOf { it.score!! * it.credit } / credits else null
        }
        fun calculate(grades: List<GradeEntity>, summary: GradeSummaryEntity? = null): GradeAnalytics {
            val attempts = grades.mapNotNull { grade ->
                val credit = grade.credit.trim().toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 } ?: return@mapNotNull null
                val raw = grade.score.trim()
                val score = raw.toDoubleOrNull()?.takeIf { it.isFinite() && it in 0.0..100.0 }
                val failed = failing.any(raw::contains)
                val passed = !failed && (score?.let { it >= 60 } ?: passing.any(raw::contains))
                if (raw.isEmpty() || (score == null && !passed && !failed)) return@mapNotNull null
                Course(grade, credit, score, passed, 1)
            }
            val effective = attempts.groupBy { course ->
                val grade = course.record
                grade.courseCode?.trim()?.takeIf { it.isNotEmpty() }?.let { "code|$it" }
                    ?: "${grade.term}|${normalizedName(grade.courseName)}|${course.credit}"
            }.values.map { group ->
                val eligible = group.filter { it.isPassed }.ifEmpty { group }
                eligible.sortedWith(scoreDescending).first().copy(attemptCount = group.size)
            }.sortedWith(compareByDescending<Course> { it.record.term }.thenBy { it.record.courseName })
            return GradeAnalytics(effective, grades.size, summary?.officialGpa, summary?.officialWeightedAverage, summary?.officialCreditPoint)
        }
        private fun normalizedName(name: String) = name.lowercase().replace(" ", "").replace("　", "")
            .replace("（", "(").replace("）", ")").replace("-", "").replace("_", "")
    }
}
