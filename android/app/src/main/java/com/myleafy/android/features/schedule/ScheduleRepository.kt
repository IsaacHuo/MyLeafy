package com.myleafy.android.features.schedule

import com.myleafy.android.core.data.local.ScheduleEventDao
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleMemoDao
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import com.myleafy.android.core.campus.ActiveAppScopeStore
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest

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
    private val activeAppScopeStore: ActiveAppScopeStore,
) : ScheduleRepository {

    override fun memos(): Flow<List<ScheduleMemoEntity>> =
        activeAppScopeStore.scope.flatMapLatest { memoDao.activeMemos(it.scopeKey) }

    override fun events(): Flow<List<ScheduleEventEntity>> =
        activeAppScopeStore.scope.flatMapLatest { eventDao.all(it.scopeKey) }

    override suspend fun addMemo(body: String, title: String?, tags: List<String>) {
        val now = System.currentTimeMillis()
        memoDao.upsert(
            ScheduleMemoEntity(
                scopeKey = activeAppScopeStore.current.scopeKey,
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
        memoDao.softDelete(
            scopeKey = activeAppScopeStore.current.scopeKey,
            id = id,
            trashedAt = System.currentTimeMillis(),
            updatedAt = System.currentTimeMillis(),
        )
    }

    override suspend fun addEvent(title: String, startsAt: Long, endsAt: Long?, location: String?, note: String?) {
        eventDao.upsert(
            ScheduleEventEntity(
                scopeKey = activeAppScopeStore.current.scopeKey,
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

    override suspend fun deleteEvent(id: String) = eventDao.delete(activeAppScopeStore.current.scopeKey, id)
}
