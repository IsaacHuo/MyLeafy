package com.myleafy.android.core.network

import kotlinx.coroutines.flow.Flow

/**
 * 学校教务客户端接口（阶段 2 由 OkHttp 实现）。
 *
 * 行为契约来自 iOS `SchoolNetworkManager`，包括：强智登录（encodeKey 算法、
 * 验证码、会话验证）、Cookie 持久化、研究生 AES 链路、课表/成绩/考试接口。
 * 阶段 1 只定义接口与结果类型，不提供实现。
 */
interface SchoolNetworkClient {

    /** 教务会话 Cookie 字典（按当前身份持久化）。 */
    val cookies: Map<String, String>

    /** 请求本科生验证码：返回验证码图片字节。需先调用 [startSession] 获得登录 key。 */
    suspend fun fetchUndergraduateCaptcha(): ByteArray

    /** 研究生登录公钥（RSA），来自 /home/stulogin 的 #pubkey。 */
    suspend fun fetchGraduatePublicKey(): String

    suspend fun loginUndergraduate(account: String, password: String, captcha: String)

    suspend fun loginGraduate(account: String, password: String, captcha: String)

    suspend fun verifyAuthenticatedSession(): Result<Unit>

    suspend fun fetchTimetable(semesterId: String): Flow<List<CourseRecord>>

    fun clearSession()
}

/** 课表记录（解析器产物，阶段 2 生效）。 */
data class CourseRecord(
    val courseName: String,
    val teacher: String,
    val classInfo: String,
    val room: String,
    val location: String,
    val dayOfWeek: Int,
    val weeks: List<Int>,
    val duration: List<Int>,
)
