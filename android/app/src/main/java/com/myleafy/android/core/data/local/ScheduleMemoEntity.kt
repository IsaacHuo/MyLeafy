package com.myleafy.android.core.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 随记本地实体（对应 iOS `ScheduleMemo`，按校园身份作用域保存）。
 * kind 取值 quickMemo / article / audio；tags 为换行分隔；
 * pinnedAt / trashedAt 为 null 表示未置顶/未删除；linkedSchedule* 关联日程。
 */
@Entity(tableName = "schedule_memos")
data class ScheduleMemoEntity(
    @PrimaryKey val id: String,
    val body: String,
    val kind: String,
    val title: String?,
    val tags: String,
    val createdAt: Long,
    val updatedAt: Long,
    val pinnedAt: Long?,
    val trashedAt: Long?,
    val linkedScheduleKind: String?,
    val linkedScheduleId: String?,
)
