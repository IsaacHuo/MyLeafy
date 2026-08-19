package com.myleafy.android.core.network

import com.myleafy.android.parsers.EmptyClassroom
import com.myleafy.android.parsers.ParsedExamRecord
import com.myleafy.android.parsers.ParsedGradeRecord
import kotlinx.coroutines.flow.Flow

/**
 * 学校教务客户端接口（OkHttp 实现）。
 *
 * 行为契约来自 iOS `SchoolNetworkManager`，包括：强智登录（encodeKey 算法、
 * 验证码、会话验证）、Cookie 持久化、课表抓取；研究生 AES 链路后续接入。
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

    /** 抓取并解析课表（强智本科）。需已登录；返回解析后的课程记录。 */
    suspend fun fetchTimetable(semesterId: String): List<CourseRecord>

    /** 抓取并解析成绩（强智 /jsxsd/kscj/cjcx_list）。 */
    suspend fun fetchGrades(): List<ParsedGradeRecord>

    /** 抓取并解析考试安排（强智 /jsxsd/xsks/xsksap_list）。 */
    suspend fun fetchExams(semesterId: String): List<ParsedExamRecord>

    /** 抓取并解析空闲教室（强智 /jsxsd/kbxx/jsjy_query2）。 */
    suspend fun fetchEmptyClassrooms(
        semesterId: String,
        week: Int,
        day: Int,
        startPeriod: Int,
        endPeriod: Int,
    ): List<EmptyClassroom>

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
