package com.myleafy.android.services.cloudflare

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

@Serializable
data class SharedTimetableCourseDto(
    val id: String,
    val course_name: String,
    val teacher: String,
    val room: String,
    val location: String,
    val day_of_week: Int,
    val weeks: List<Int>,
    val duration: List<Int>,
)

@Serializable
data class SharedTimetableSnapshotDto(
    val id: String,
    val owner_id: String,
    val semester_id: String,
    val courses: List<SharedTimetableCourseDto>,
    val owner: com.myleafy.android.shared.model.ProfileDto? = null,
    val course_count: Int,
    val published_at: String,
    val created_at: String,
    val updated_at: String,
)

@Serializable
data class TimetableShareMemberDto(
    val id: String,
    val owner_id: String,
    val viewer_id: String,
    val viewer: com.myleafy.android.shared.model.ProfileDto? = null,
    val owner: com.myleafy.android.shared.model.ProfileDto? = null,
    val created_at: String,
    val updated_at: String,
    val revoked_at: String? = null,
)

@Serializable
data class TimetableInviteDto(
    val id: String,
    val owner_id: String,
    val semester_id: String,
    val expires_at: String,
    val accepted_by: String? = null,
    val accepted_at: String? = null,
    val created_at: String,
    val code: String? = null,
)

class TimetableSharingService(private val client: BackendClient) {
    suspend fun isBackendAvailable(): Boolean = true
    suspend fun publish(campusId: String, ownerId: String, semesterId: String, courses: List<SharedTimetableCourseDto>): SharedTimetableSnapshotDto {
        require(courses.isNotEmpty()) { "本地课表为空，请先同步课表" }
        return client.request("/v1/timetables", "PUT", buildJsonObject {
            put("semester_id", semesterId); put("courses", client.json.encodeToJsonElement(courses))
        })
    }
    private suspend fun snapshots(semesterId: String): List<SharedTimetableSnapshotDto> =
        client.request("/v1/timetables", query = mapOf("semester_id" to semesterId))
    suspend fun mySnapshot(campusId: String, ownerId: String, semesterId: String): SharedTimetableSnapshotDto? =
        snapshots(semesterId).firstOrNull { it.owner_id.equals(ownerId, true) }
    suspend fun viewableSnapshots(campusId: String, ownerId: String, semesterId: String): List<SharedTimetableSnapshotDto> =
        snapshots(semesterId).filterNot { it.owner_id.equals(ownerId, true) }
    suspend fun members(campusId: String, ownerId: String): List<TimetableShareMemberDto> = client.request("/v1/timetables/members")
    suspend fun invites(campusId: String, ownerId: String): List<TimetableInviteDto> = client.request("/v1/timetables/invites")
    suspend fun createInvite(): TimetableInviteDto = client.request("/v1/timetables/invites", "POST")
    suspend fun accept(code: String): SharedTimetableSnapshotDto =
        client.request("/v1/timetables/invites/accept", "POST", buildJsonObject { put("code", normalizeCode(code)) })
    suspend fun revoke(ownerId: String, viewerId: String) {
        val member = client.request<List<TimetableShareMemberDto>>("/v1/timetables/members")
            .firstOrNull { it.viewer_id.equals(viewerId, true) } ?: error("共享关系已不存在")
        client.requestText("/v1/timetables/members/${member.id}", "DELETE")
    }
    suspend fun stopSharing() { client.requestText("/v1/timetables/stop", "POST") }
    suspend fun leave(ownerId: String) {
        val member = client.request<List<TimetableShareMemberDto>>("/v1/timetables/members", query = mapOf("direction" to "incoming"))
            .firstOrNull { it.owner_id.equals(ownerId, true) } ?: error("共享关系已不存在")
        client.requestText("/v1/timetables/members/${member.id}/leave", "POST")
    }
    companion object {
        fun normalizeCode(code: String): String = code.uppercase().filter { it in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567" }
    }
}
