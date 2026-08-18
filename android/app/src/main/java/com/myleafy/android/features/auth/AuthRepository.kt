package com.myleafy.android.features.auth

/**
 * 登录仓储接口。学校登录（强智/研究生）由 SchoolNetworkClient 提供，
 * 阶段 2 接入；阶段 1.5 占位实现如实返回失败，UI 展示错误状态。
 */
interface AuthRepository {
    val hasCachedIdentity: Boolean

    /** 返回 Result.failure 表示未接入或登录失败；Success 表示登录成功。 */
    suspend fun loginUndergraduate(account: String, password: String, captcha: String): Result<Unit>
}

class PlaceholderAuthRepository : AuthRepository {
    override val hasCachedIdentity: Boolean = false

    override suspend fun loginUndergraduate(account: String, password: String, captcha: String): Result<Unit> =
        Result.failure(IllegalStateException("教务登录将在阶段 2 接入"))
}
