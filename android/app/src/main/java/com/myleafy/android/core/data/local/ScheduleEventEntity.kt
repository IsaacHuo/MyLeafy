package com.myleafy.android.core.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 个人日程实体（对应 iOS `CustomScheduleEvent`；iOS 用 UserDefaults JSON，
 * Android 用 Room，字段语义一致）。时间存 epoch millis。
 */
@Entity(tableName = "schedule_events")
data class ScheduleEventEntity(
    @PrimaryKey val id: String,
    val title: String,
    val startsAt: Long,
    val endsAt: Long?,
    val location: String?,
    val note: String?,
    val minutesBefore: Int,
)
