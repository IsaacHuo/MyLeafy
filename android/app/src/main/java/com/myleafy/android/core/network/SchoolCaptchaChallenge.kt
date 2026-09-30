package com.myleafy.android.core.network

/** In-memory challenge. Never serialize or log the key, image or cookies. */
class SchoolCaptchaChallenge(
    val imageBytes: ByteArray,
    internal val key: String = "",
    internal val candidateCookies: Map<String, String> = emptyMap(),
    internal val scope: String? = null,
    internal val generation: Long = 0,
    internal val owner: Any? = null,
) {
    internal val consumed = java.util.concurrent.atomic.AtomicBoolean(false)
    override fun toString() = "SchoolCaptchaChallenge(redacted)"
}
