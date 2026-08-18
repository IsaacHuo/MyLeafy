package com.myleafy.android.core.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 成绩本地实体。credit/score 保持原始字符串（与 iOS `Grade` 一致），
 * 避免数值化丢失；term 为开课学期。
 */
@Entity(tableName = "grades")
data class GradeEntity(
    @PrimaryKey val id: String,
    val term: String,
    val courseName: String,
    val credit: String,
    val score: String,
    val type: String,
)
