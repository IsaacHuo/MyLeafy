package com.myleafy.android.features.timetable

import com.myleafy.android.core.data.local.CourseDao
import com.myleafy.android.core.data.local.CourseEntity
import kotlinx.coroutines.flow.Flow

/**
 * 课表仓储接口。学校教务是权威来源，Room 是本地副本；
 * 远程学期运行配置（semester_runtime_configs）在后续阶段接入。
 */
interface TimetableRepository {
    fun coursesForSemester(semesterId: String): Flow<List<CourseEntity>>
}

class RoomTimetableRepository(
    private val courseDao: CourseDao,
) : TimetableRepository {
    override fun coursesForSemester(semesterId: String): Flow<List<CourseEntity>> =
        courseDao.coursesForSemester(semesterId)
}
