package com.myleafy.android.services.cloudflare

import com.myleafy.android.services.TimetableSharingService
import com.myleafy.android.services.supabase.*
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put

class CloudflareTimetableSharingService(private val client: MyLeafyBackendClient) : TimetableSharingService {
    override suspend fun isBackendAvailable(): Boolean {
        client.request("/v1/timetables")
        return true
    }

    override suspend fun publish(campusId: String, ownerId: String, semesterId: String, courses: List<SharedTimetableCourseDto>): SharedTimetableSnapshotDto {
        require(courses.isNotEmpty()) { "本地课表为空，请先同步课表" }
        return client.decodeRequest("/v1/timetables", "PUT", buildJsonObject {
            put("semester_id", semesterId); put("courses", backendJson.encodeToJsonElement(courses))
        })
    }

    private suspend fun snapshots(semesterId: String): List<SharedTimetableSnapshotDto> =
        client.decodeRequest("/v1/timetables", query = mapOf("semester_id" to semesterId))

    override suspend fun mySnapshot(campusId: String, ownerId: String, semesterId: String): SharedTimetableSnapshotDto? =
        snapshots(semesterId).firstOrNull { it.owner_id == ownerId }

    override suspend fun viewableSnapshots(campusId: String, ownerId: String, semesterId: String): List<SharedTimetableSnapshotDto> =
        snapshots(semesterId).filter { it.owner_id != ownerId }

    override suspend fun members(campusId: String, ownerId: String): List<TimetableShareMemberDto> =
        client.decodeRequest("/v1/timetables/members")

    override suspend fun invites(campusId: String, ownerId: String): List<TimetableInviteDto> =
        client.decodeRequest("/v1/timetables/invites")

    override suspend fun createInvite(): TimetableInviteDto = client.decodeRequest("/v1/timetables/invites", "POST")
    override suspend fun accept(code: String): SharedTimetableSnapshotDto =
        client.decodeRequest("/v1/timetables/invites/accept", "POST", buildJsonObject { put("code", TimetableSharingService.normalizeCode(code)) })

    override suspend fun revoke(ownerId: String, viewerId: String) {
        val memberships = client.decodeRequest<List<TimetableShareMemberDto>>("/v1/timetables/members")
        val member = memberships.firstOrNull { it.owner_id == ownerId && it.viewer_id == viewerId }
            ?: error("共享关系不存在或已撤销")
        client.request("/v1/timetables/members/${apiID(member.id)}", "DELETE")
    }

    override suspend fun stopSharing() { client.request("/v1/timetables/stop", "POST") }
    override suspend fun leave(ownerId: String) {
        val memberships = client.decodeRequest<List<TimetableShareMemberDto>>("/v1/timetables/members", query = mapOf("direction" to "incoming"))
        val member = memberships.firstOrNull { it.owner_id == ownerId } ?: error("共享关系不存在或已撤销")
        client.request("/v1/timetables/members/${apiID(member.id)}/leave", "POST")
    }
}
