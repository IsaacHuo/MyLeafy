package com.myleafy.android.features.timetable

import com.myleafy.android.core.data.local.CourseDao
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.network.SchoolNetworkClient
import com.myleafy.android.core.network.AcademicStage
import com.myleafy.android.core.network.TimetableRefreshResult
import kotlinx.coroutines.flow.first
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.ExperimentalCoroutinesApi

/**
 * 课表仓储接口。学校教务是权威来源，Room 是本地副本；
 * 远程学期运行配置（semester_runtime_configs）在后续阶段接入。
 */
interface TimetableRepository {
    fun coursesForSemester(semesterId: String): Flow<List<CourseEntity>>

    /** 从教务抓取当前学期课表并写入 Room。失败时抛出 [Exception]。 */
    suspend fun refresh(semesterId: String, onStage: (AcademicStage) -> Unit = {}): TimetableRefreshResult
}

/** 线上仓储：教务抓取（OkHttp + jsoup）→ 解析 → Room 落库。 */
@OptIn(ExperimentalCoroutinesApi::class)
class LiveTimetableRepository(
    private val client: SchoolNetworkClient,
    private val courseDao: CourseDao,
    private val activeAppScopeStore: ActiveAppScopeStore,
) : TimetableRepository {

    override fun coursesForSemester(semesterId: String): Flow<List<CourseEntity>> =
        activeAppScopeStore.scope.flatMapLatest { scope ->
            courseDao.coursesForSemester(scope.scopeKey, semesterId)
        }

    override suspend fun refresh(semesterId: String, onStage: (AcademicStage) -> Unit): TimetableRefreshResult {
        val scopeKey = activeAppScopeStore.current.scopeKey
        val previous = courseDao.coursesForSemester(scopeKey, semesterId).first()
        val records = client.fetchTimetable(semesterId, onStage)
        val entities = records.map { r ->
            CourseEntity(
                scopeKey = scopeKey,
                id = UUID.nameUUIDFromBytes(
                    listOf(
                        semesterId,
                        r.courseName,
                        r.teacher,
                        r.classInfo,
                        r.location,
                        r.room,
                        r.dayOfWeek.toString(),
                        r.weeks.joinToString(","),
                        r.duration.joinToString(","),
                    ).joinToString("|").toByteArray(Charsets.UTF_8),
                ).toString(),
                sourceSemesterID = semesterId,
                courseName = r.courseName,
                teacher = r.teacher,
                classInfo = r.classInfo,
                room = r.room,
                location = r.location,
                dayOfWeek = r.dayOfWeek,
                weeks = r.weeks,
                duration = r.duration,
            )
        }
        if (activeAppScopeStore.current.scopeKey != scopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
        onStage(AcademicStage.SAVING_TIMETABLE)
        courseDao.replaceForSemester(scopeKey, semesterId, entities)
        return TimetableRefreshResult(entities.map { it.courseName }.distinct().size, entities.size,
            previous.sortedBy { it.id } != entities.sortedBy { it.id })
    }
}
