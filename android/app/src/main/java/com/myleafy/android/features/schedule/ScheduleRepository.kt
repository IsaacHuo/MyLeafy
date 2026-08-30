package com.myleafy.android.features.schedule

import com.myleafy.android.core.data.local.ScheduleEventDao
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleMemoDao
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import com.myleafy.android.core.campus.ActiveAppScopeStore
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.ExperimentalCoroutinesApi

/**
 * 日迹仓储（随记 + 个人日程）。本地为权威来源，Room 持久化；
 * 学校课程/考试/校历不进入随记或日程（见 state/ARCHITECTURE.md §11）。
 */
interface ScheduleRepository {
    fun memos(): Flow<List<ScheduleMemoEntity>>
    fun events(): Flow<List<ScheduleEventEntity>>
    fun eventsInRange(startInclusive: Long, endExclusive: Long): Flow<List<ScheduleEventEntity>>

    suspend fun memo(id: String): ScheduleMemoEntity?
    suspend fun event(id: String): ScheduleEventEntity?
    suspend fun saveMemo(id: String?, body: String, title: String?, tags: List<String>): String
    suspend fun deleteMemo(id: String)
    suspend fun saveEvent(
        id: String?,
        title: String,
        startsAt: Long,
        endsAt: Long,
        location: String?,
        note: String?,
    ): String
    suspend fun deleteEvent(id: String)
}

@OptIn(ExperimentalCoroutinesApi::class)
class RoomScheduleRepository(
    private val memoDao: ScheduleMemoDao,
    private val eventDao: ScheduleEventDao,
    private val activeAppScopeStore: ActiveAppScopeStore,
) : ScheduleRepository {

    override fun memos(): Flow<List<ScheduleMemoEntity>> =
        activeAppScopeStore.scope.flatMapLatest { memoDao.activeMemos(it.scopeKey) }

    override fun events(): Flow<List<ScheduleEventEntity>> =
        activeAppScopeStore.scope.flatMapLatest { eventDao.all(it.scopeKey) }

    override fun eventsInRange(startInclusive: Long, endExclusive: Long): Flow<List<ScheduleEventEntity>> =
        activeAppScopeStore.scope.flatMapLatest {
            eventDao.inRange(it.scopeKey, startInclusive, endExclusive)
        }

    override suspend fun memo(id: String): ScheduleMemoEntity? =
        memoDao.memoById(activeAppScopeStore.current.scopeKey, id)

    override suspend fun event(id: String): ScheduleEventEntity? =
        eventDao.byId(activeAppScopeStore.current.scopeKey, id)

    override suspend fun saveMemo(id: String?, body: String, title: String?, tags: List<String>): String {
        val now = System.currentTimeMillis()
        val scopeKey = activeAppScopeStore.current.scopeKey
        val resolvedId = id ?: UUID.randomUUID().toString()
        val existing = id?.let { memoDao.memoById(scopeKey, it) }
        memoDao.upsert(
            ScheduleMemoEntity(
                scopeKey = scopeKey,
                id = resolvedId,
                body = body,
                kind = existing?.kind ?: "quickMemo",
                title = title?.takeIf { it.isNotBlank() },
                tags = tags.joinToString("\n"),
                createdAt = existing?.createdAt ?: now,
                updatedAt = now,
                pinnedAt = existing?.pinnedAt,
                trashedAt = null,
                linkedScheduleKind = existing?.linkedScheduleKind,
                linkedScheduleId = existing?.linkedScheduleId,
            ),
        )
        return resolvedId
    }

    override suspend fun deleteMemo(id: String) {
        memoDao.softDelete(
            scopeKey = activeAppScopeStore.current.scopeKey,
            id = id,
            trashedAt = System.currentTimeMillis(),
            updatedAt = System.currentTimeMillis(),
        )
    }

    override suspend fun saveEvent(
        id: String?,
        title: String,
        startsAt: Long,
        endsAt: Long,
        location: String?,
        note: String?,
    ): String {
        require(endsAt > startsAt) { "结束时间必须晚于开始时间" }
        val resolvedId = id ?: UUID.randomUUID().toString()
        val existing = id?.let { eventDao.byId(activeAppScopeStore.current.scopeKey, it) }
        eventDao.upsert(
            ScheduleEventEntity(
                scopeKey = activeAppScopeStore.current.scopeKey,
                id = resolvedId,
                title = title,
                startsAt = startsAt,
                endsAt = endsAt,
                location = location?.takeIf { it.isNotBlank() },
                note = note?.takeIf { it.isNotBlank() },
                minutesBefore = existing?.minutesBefore ?: 0,
            ),
        )
        return resolvedId
    }

    override suspend fun deleteEvent(id: String) = eventDao.delete(activeAppScopeStore.current.scopeKey, id)
}
