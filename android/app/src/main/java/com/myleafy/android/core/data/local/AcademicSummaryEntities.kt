package com.myleafy.android.core.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

/** 学校官方成绩排名缓存；学校页面仍是权威来源。 */
@Entity(tableName = "grade_rankings")
data class GradeRankingEntity(
    @PrimaryKey val id: String,
    val term: String,
    val rankingRange: String,
    val rank: Int,
    val totalCount: Int?,
    val metricText: String,
)

/** 成绩页官方汇总缓存。固定单行，缺失字段保持 null，不自行估算 GPA。 */
@Entity(tableName = "grade_summaries")
data class GradeSummaryEntity(
    @PrimaryKey val id: String = OFFICIAL_ID,
    val officialGpa: Double?,
    val officialWeightedAverage: Double?,
    val officialCreditPoint: Double?,
) {
    companion object {
        const val OFFICIAL_ID = "official"
    }
}
