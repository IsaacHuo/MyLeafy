package com.myleafy.android.core.data.local

import androidx.room.Entity

/**
 * 考试安排本地实体（对应 iOS `ExamArrangement`）。
 * date 为 yyyy-MM-dd，start/end 为 HH:mm。
 */
@Entity(tableName = "exams", primaryKeys = ["scopeKey", "id"])
data class ExamEntity(
    val scopeKey: String,
    val id: Int,
    val courseId: String,
    val name: String,
    val date: String,
    val start: String,
    val end: String,
    val location: String,
)
