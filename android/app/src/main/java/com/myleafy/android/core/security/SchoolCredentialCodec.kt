package com.myleafy.android.core.security

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

object SchoolCredentialCodec {
    private val json = Json { ignoreUnknownKeys = true }
    fun encode(value: StoredSchoolCredential): String = json.encodeToString(value)
    fun decode(raw: String): StoredSchoolCredential? = runCatching {
        val value = if (raw.startsWith("{")) json.decodeFromString<StoredSchoolCredential>(raw) else {
            val head = raw.split('|', limit = 4)
            require(head.size == 4)
            val last = head[3].lastIndexOf('|')
            require(last >= 0)
            val escaped = head[3].substring(0, last)
            require(!head[2].contains('|') && escaped.replace("||", "").none { it == '|' })
            StoredSchoolCredential(head[0], head[1], head[2], escaped.replace("||", "|"), head[3].substring(last + 1).toLong())
        }
        require(value.campusId == "bjfu" && value.portal in listOf("undergraduate", "graduate"))
        require(value.account.isNotBlank() && value.password.isNotEmpty() && value.savedAt >= 0)
        value
    }.getOrNull()
}
