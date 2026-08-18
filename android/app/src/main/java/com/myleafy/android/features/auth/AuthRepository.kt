package com.myleafy.android.features.auth

/**
 * 登录仓储接口。学校登录（强智/研究生）由 SchoolNetworkClient 提供，
 * 阶段 2 接入；此处仅定义后续 Auth 流程所需的会话事实。
 */
interface AuthRepository {
    val hasCachedIdentity: Boolean
}

class PlaceholderAuthRepository : AuthRepository {
    override val hasCachedIdentity: Boolean = false
}
