package com.myleafy.android.features.campus

import com.myleafy.android.core.network.SchoolNetworkClient
import com.myleafy.android.parsers.EmptyClassroom

/**
 * 自习安排仓储：空闲教室查询（教务权威，按需抓取，不持久化）。
 */
interface ClassroomRepository {
    suspend fun emptyClassrooms(
        semesterId: String,
        week: Int,
        day: Int,
        startPeriod: Int,
        endPeriod: Int,
    ): List<EmptyClassroom>
}

class LiveClassroomRepository(
    private val client: SchoolNetworkClient,
) : ClassroomRepository {
    override suspend fun emptyClassrooms(
        semesterId: String,
        week: Int,
        day: Int,
        startPeriod: Int,
        endPeriod: Int,
    ): List<EmptyClassroom> =
        client.fetchEmptyClassrooms(semesterId, week, day, startPeriod, endPeriod)
}
