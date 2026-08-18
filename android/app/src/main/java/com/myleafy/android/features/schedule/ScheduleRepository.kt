package com.myleafy.android.features.schedule

import com.myleafy.android.core.data.local.ScheduleEventDao
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleMemoDao
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import java.util.UUID
import kotlinx.coroutines.flow.Flow

/**
 * 日迹仓储（随记 + 个人日程）。本地为权威来源，Room 持久化；
 * 学校课程/考试/校历不进入随记或日程（见 state/ARCHITECTURE.md §11）。
 */
interface ScheduleRepository {
    fun memos(): Flow<List<ScheduleMemoEntity>>
    fun events(): Flow<List<ScheduleEventEntity>>

    suspend fun addMemo(body: String, title: String?, tags: List<String>)
    suspend fun deleteMemo(id: String)
    suspend fun addEvent(title: String, startsAt: Long, endsAt: Long?, location: String?, note: String?)
    suspend fun deleteEvent(id: String)
}

class RoomScheduleRepository(
    private val memoDao: ScheduleMemoDao,
    private val eventDao: ScheduleEventDao,
) : ScheduleRepository {

    override fun memos(): Flow<List<ScheduleMemoEntity>> = memoDao.activeMemos()

    override fun events(): Flow<List<ScheduleEventEntity>> = eventDao.all()

    override suspend fun addMemo(body: String, title: String?, tags: List<String>) {
        val now = System.currentTimeMillis()
        memoDao.upsert(
            ScheduleMemoEntity(
                id = UUID.randomUUID().toString(),
                body = body,
                kind = "quickMemo",
                title = title?.takeIf { it.isNotBlank() },
                tags = tags.joinToString("\n"),
                createdAt = now,
                updatedAt = now,
                pinnedAt = null,
                trashedAt = null,
                linkedScheduleKind = null,
                linkedScheduleId = null,
            ),
        )
    }

    override suspend fun deleteMemo(id: String) {
        memoDao.softDelete(id, trashedAt = System.currentTimeMillis(), updatedAt = System.currentTimeMillis())
    }

    override suspend fun addEvent(title: String, startsAt: Long, endsAt: Long?, location: String?, note: String?) {
        eventDao.upsert(
            ScheduleEventEntity(
                id = UUID.randomUUID().toString(),
                title = title,
                startsAt = startsAt,
                endsAt = endsAt,
                location = location?.takeIf { it.isNotBlank() },
                note = note?.takeIf { it.isNotBlank() },
                minutesBefore = 0,
            ),
        )
    }

    override suspend fun deleteEvent(id: String) = eventDao.delete(id)
}
