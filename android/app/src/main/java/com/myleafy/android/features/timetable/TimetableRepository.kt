package com.myleafy.android.features.timetable

import com.myleafy.android.core.data.local.CourseDao
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.core.network.SchoolNetworkClient
import java.util.UUID
import kotlinx.coroutines.flow.Flow

/**
 * 课表仓储接口。学校教务是权威来源，Room 是本地副本；
 * 远程学期运行配置（semester_runtime_configs）在后续阶段接入。
 */
interface TimetableRepository {
    fun coursesForSemester(semesterId: String): Flow<List<CourseEntity>>

    /** 从教务抓取当前学期课表并写入 Room。失败时抛出 [Exception]。 */
    suspend fun refresh(semesterId: String)
}

/** 线上仓储：教务抓取（OkHttp + jsoup）→ 解析 → Room 落库。 */
class LiveTimetableRepository(
    private val client: SchoolNetworkClient,
    private val courseDao: CourseDao,
) : TimetableRepository {

    override fun coursesForSemester(semesterId: String): Flow<List<CourseEntity>> =
        courseDao.coursesForSemester(semesterId)

    override suspend fun refresh(semesterId: String) {
        val records = client.fetchTimetable(semesterId)
        val entities = records.map { r ->
            CourseEntity(
                id = UUID.randomUUID().toString(),
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
        courseDao.clearForSemester(semesterId)
        courseDao.upsertAll(entities)
    }
}
