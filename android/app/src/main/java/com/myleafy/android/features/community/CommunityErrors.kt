package com.myleafy.android.features.community

/** 将后端稳定错误码转换为可操作的用户提示，同时保留未知错误文本用于排查。 */
internal fun Throwable.toCommunityMessage(fallback: String): String {
    val raw = message.orEmpty()
    return when {
        "COMMUNITY_PROFILE_REQUIRED" in raw -> "请先登录教务并初始化社区身份"
        "PROFILE_COMPLETION_REQUIRED" in raw -> "请先在“我的”中完善社区昵称与资料"
        "COMMUNITY_TERMS_REQUIRED" in raw -> "请先阅读并同意社区规范"
        "CANNOT_LIKE_OWN_POST" in raw -> "不能点赞自己发布的帖子"
        "COMMUNITY_POST_NOT_FOUND" in raw -> "帖子不存在或当前不可见"
        "RATE_LIMIT" in raw || "rate limit" in raw.lowercase() -> "操作过于频繁，请稍后再试"
        else -> fallback
    }
}
