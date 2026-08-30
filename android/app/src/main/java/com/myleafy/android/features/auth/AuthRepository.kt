package com.myleafy.android.features.auth

/**
 * 登录仓储接口。学校登录（强智/研究生）由 SchoolNetworkClient 提供。
 */
interface AuthRepository {
    val hasCachedIdentity: Boolean

    /** 获取本科生验证码图片字节（自动完成 key 刷新与 Cookie 清理）。 */
    suspend fun fetchUndergraduateCaptcha(): ByteArray

    /** 返回 Result.failure 表示登录失败；Success 表示登录成功（已建立会话）。 */
    suspend fun loginUndergraduate(account: String, password: String, captcha: String): Result<Unit>

    suspend fun logout()
}

class PlaceholderAuthRepository : AuthRepository {
    override val hasCachedIdentity: Boolean = false

    override suspend fun fetchUndergraduateCaptcha(): ByteArray =
        throw NotImplementedError("教务登录将在 M2.2 接入")

    override suspend fun loginUndergraduate(account: String, password: String, captcha: String): Result<Unit> =
        Result.failure(IllegalStateException("教务登录将在 M2.2 接入"))

    override suspend fun logout() = Unit
}
