package com.myleafy.android.features.community

import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLPeerUnverifiedException

/** 将后端稳定错误码转换为可操作的用户提示，同时保留未知错误文本用于排查。 */
internal fun Throwable.toCommunityMessage(fallback: String): String {
    val causes = generateSequence(this) { it.cause }.toList()
    val raw = causes.mapNotNull { it.message }.joinToString("\n")
    val normalized = raw.lowercase()
    return when {
        causes.any { it is SSLPeerUnverifiedException } ||
            ("hostname" in normalized && "not verified" in normalized) ->
            "当前网络替换了 MyLeafy 的安全证书（bjfu-wifi 的登录/拦截页会返回 *.bjfu.edu.cn 证书）。请先完成校园网登录，或切换到移动数据/全局 VPN 后重试。"
        causes.any { it is UnknownHostException } ->
            "无法解析社区服务地址，请检查网络或 DNS 设置后重试"
        causes.any { it is SocketTimeoutException || it is ConnectException } ->
            "无法连接社区服务，请检查网络后重试"
        "COMMUNITY_PROFILE_REQUIRED" in raw -> "请先登录教务并初始化社区身份"
        "PROFILE_COMPLETION_REQUIRED" in raw -> "请先在“我的”中完善社区昵称与资料"
        "COMMUNITY_TERMS_REQUIRED" in raw -> "请先阅读并同意社区规范"
        "CANNOT_LIKE_OWN_POST" in raw -> "不能点赞自己发布的帖子"
        "COMMUNITY_POST_NOT_FOUND" in raw -> "帖子不存在或当前不可见"
        "RATE_LIMIT" in raw || "rate limit" in raw.lowercase() -> "操作过于频繁，请稍后再试"
        raw.isBlank() -> fallback
        else -> "$fallback：$raw"
    }
}

/** TLS 主机名/证书被替换属于不可恢复的网络环境问题，重连不会自愈。 */
internal fun Throwable.isPermanentTlsFailure(): Boolean {
    val causes = generateSequence(this) { it.cause }.toList()
    val normalized = causes.mapNotNull { it.message }.joinToString("\n").lowercase()
    return causes.any { it is SSLPeerUnverifiedException } ||
        ("hostname" in normalized && "not verified" in normalized) ||
        ("certificate" in normalized && "not verified" in normalized)
}
