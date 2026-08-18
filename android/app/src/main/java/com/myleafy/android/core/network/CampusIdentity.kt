package com.myleafy.android.core.network

import com.myleafy.android.core.campus.CampusID
import java.security.MessageDigest

/**
 * 校园身份（对应 iOS `CampusIdentity`）。用于本地数据与凭据按身份隔离。
 * `scopeKey` 为身份串的 SHA-256 前 12 个十六进制字符，与 iOS 一致。
 */
data class CampusIdentity(
    val campusId: CampusID,
    val eduId: String,
    val displayName: String?,
    val portal: SchoolPortal,
    val kind: IdentityKind,
) {
    val scopeKey: String
        get() = sha256(scopeSource).take(12)

    private val scopeSource: String
        get() = when (kind) {
            IdentityKind.SCHOOL_PORTAL ->
                "${campusId.rawValue}:${kind.rawValue}:${portal.rawValue}:${eduId.lowercase()}"
            IdentityKind.CUSTOM_SUPABASE ->
                "${campusId.rawValue}:${kind.rawValue}:${eduId.lowercase()}"
        }

    enum class IdentityKind(val rawValue: String) {
        SCHOOL_PORTAL("schoolPortal"),
        CUSTOM_SUPABASE("customSupabase"),
    }

    private companion object {
        fun sha256(input: String): String {
            val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }
}
