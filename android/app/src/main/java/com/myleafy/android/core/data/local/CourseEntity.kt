package com.myleafy.android.core.data.local

import androidx.room.Entity

/**
 * 课程本地实体（Room）。字段语义与 iOS `Course`（SwiftData）一致：
 * dayOfWeek 1=周一 … 7=周日，weeks 为学期周次，duration 为节次。
 *
 * 权威来源仍是学校教务，Room 只是本地副本。
 */
@Entity(tableName = "courses", primaryKeys = ["scopeKey", "id"])
data class CourseEntity(
    val scopeKey: String,
    val id: String,
    val sourceSemesterID: String,
    val courseName: String,
    val teacher: String,
    val classInfo: String,
    val room: String,
    val location: String,
    val dayOfWeek: Int,
    val weeks: List<Int>,
    val duration: List<Int>,
)
