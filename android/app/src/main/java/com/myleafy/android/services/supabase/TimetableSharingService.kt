package com.myleafy.android.services.supabase

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc
import java.security.SecureRandom
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put

@Serializable
private data class BackendCapabilityDto(val features: Map<String, Boolean> = emptyMap())

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

class TimetableSharingService(private val client: SupabaseClient) {
    suspend fun isBackendAvailable(): Boolean = runCatching {
        client.postgrest.rpc("backend_capabilities_v1").decodeAs<BackendCapabilityDto>()
            .features["timetable_sharing"] == true
    }.getOrDefault(false)
    suspend fun publish(
        campusId: String,
        ownerId: String,
        semesterId: String,
        courses: List<SharedTimetableCourseDto>,
    ): SharedTimetableSnapshotDto {
        require(courses.isNotEmpty()) { "本地课表为空，请先同步课表" }
        val payload = buildJsonObject {
            put("campus_id", campusId)
            put("owner_id", ownerId)
            put("semester_id", semesterId)
            put("courses", kotlinx.serialization.json.Json.encodeToJsonElement(courses))
            put("course_count", courses.size)
            put("published_at", java.time.Instant.now().toString())
        }
        return mapSharingErrors {
            client.postgrest["timetable_snapshots"].upsert(payload) {
                onConflict = "owner_id,semester_id"
                select()
            }.decodeSingle()
        }
    }

    suspend fun mySnapshot(campusId: String, ownerId: String, semesterId: String): SharedTimetableSnapshotDto? =
        mapSharingErrors {
            client.postgrest["timetable_snapshots"].select {
                filter {
                    eq("campus_id", campusId)
                    eq("owner_id", ownerId)
                    eq("semester_id", semesterId)
                }
                limit(1)
            }.decodeList<SharedTimetableSnapshotDto>().firstOrNull()
        }

    suspend fun viewableSnapshots(campusId: String, ownerId: String, semesterId: String): List<SharedTimetableSnapshotDto> =
        mapSharingErrors {
            client.postgrest["timetable_snapshots"].select {
                filter {
                    eq("campus_id", campusId)
                    eq("semester_id", semesterId)
                    neq("owner_id", ownerId)
                }
                order("published_at", Order.DESCENDING)
            }.decodeList()
        }

    suspend fun members(campusId: String, ownerId: String): List<TimetableShareMemberDto> = mapSharingErrors {
        client.postgrest["timetable_share_members"].select {
            filter {
                eq("campus_id", campusId)
                eq("owner_id", ownerId)
                exact("revoked_at", null)
            }
            order("created_at", Order.DESCENDING)
        }.decodeList()
    }

    suspend fun invites(campusId: String, ownerId: String): List<TimetableInviteDto> = mapSharingErrors {
        client.postgrest["timetable_invites"].select {
            filter {
                eq("campus_id", campusId)
                eq("owner_id", ownerId)
            }
            order("created_at", Order.DESCENDING)
            limit(20)
        }.decodeList()
    }

    suspend fun createInvite(): TimetableInviteDto {
        repeat(3) {
            val code = generateCode()
            try {
                val result = client.postgrest.rpc(
                    "create_timetable_invite",
                    buildJsonObject { put("p_code", code) },
                ).decodeList<TimetableInviteDto>().firstOrNull()
                    ?: error("邀请码创建失败，请稍后重试")
                return result.copy(code = code)
            } catch (error: Throwable) {
                if (!error.message.orEmpty().contains("INVITE_CODE_COLLISION")) throw mapSharingError(error)
            }
        }
        throw IllegalStateException("邀请码生成冲突，请重新生成一次")
    }

    suspend fun accept(code: String): SharedTimetableSnapshotDto = mapSharingErrors {
        client.postgrest.rpc(
            "accept_timetable_invite",
            buildJsonObject { put("p_code", normalizeCode(code)) },
        ).decodeList<SharedTimetableSnapshotDto>().firstOrNull()
            ?: error("接受邀请失败，请稍后重试")
    }

    suspend fun revoke(ownerId: String, viewerId: String) = mapSharingErrors {
        client.postgrest.rpc(
            "revoke_timetable_share",
            buildJsonObject {
                put("p_owner_id", ownerId)
                put("p_viewer_id", viewerId)
            },
        )
        Unit
    }

    suspend fun stopSharing() = mapSharingErrors {
        client.postgrest.rpc("stop_timetable_sharing")
        Unit
    }

    suspend fun leave(ownerId: String) = mapSharingErrors {
        client.postgrest.rpc(
            "leave_timetable_share",
            buildJsonObject { put("p_owner_id", ownerId) },
        )
        Unit
    }

    private fun generateCode(): String = buildString(12) {
        repeat(12) { append(Alphabet[random.nextInt(Alphabet.length)]) }
    }

    companion object {
        private const val Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ234567"
        private val random = SecureRandom()

        fun normalizeCode(code: String): String = code.uppercase().filter { it in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567" }
    }
}

private inline fun <T> mapSharingErrors(block: () -> T): T = try {
    block()
} catch (error: Throwable) {
    throw mapSharingError(error)
}

private fun mapSharingError(error: Throwable): IllegalStateException {
    val raw = error.message.orEmpty()
    val message = when {
        "MISSING_PROFILE" in raw -> "共享课表需要先建立社区身份，请稍后重试"
        "TIMETABLE_NOT_PUBLISHED" in raw -> "请先发布或更新你的课表，再生成邀请码"
        "INVALID_INVITE_CODE" in raw -> "邀请码无效，请检查后重新输入"
        "INVITE_EXPIRED" in raw -> "邀请码已过期，请让对方重新生成"
        "INVITE_USED" in raw -> "邀请码已经被使用，请让对方重新生成"
        "INVITE_SELF" in raw -> "不能接受自己的共享课表邀请码"
        "INVITE_CODE_COLLISION" in raw -> "邀请码生成冲突，请重新生成一次"
        "NOT_SHARE_OWNER" in raw -> "你没有权限撤销这条共享关系"
        "function digest" in raw || "hash_timetable_invite_code" in raw ||
            ("column reference" in raw && "ambiguous" in raw) -> "共享课表服务正在更新，请稍后重试"
        else -> raw.ifBlank { "共享课表操作失败" }
    }
    return IllegalStateException(message, error)
}
