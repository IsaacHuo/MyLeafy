package com.myleafy.android.core.data.local

import androidx.room.Entity

/** 学校官方成绩排名缓存；学校页面仍是权威来源。 */
@Entity(tableName = "grade_rankings", primaryKeys = ["scopeKey", "id"])
data class GradeRankingEntity(
    val scopeKey: String,
    val id: String,
    val term: String,
    val rankingRange: String,
    val rank: Int,
    val totalCount: Int?,
    val metricText: String,
)

/** 成绩页官方汇总缓存。固定单行，缺失字段保持 null，不自行估算 GPA。 */
@Entity(tableName = "grade_summaries", primaryKeys = ["scopeKey", "id"])
data class GradeSummaryEntity(
    val scopeKey: String,
    val id: String = OFFICIAL_ID,
    val officialGpa: Double?,
    val officialWeightedAverage: Double?,
    val officialCreditPoint: Double?,
) {
    companion object {
        const val OFFICIAL_ID = "official"
    }
}
