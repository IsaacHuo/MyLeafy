package com.myleafy.android.core.network.okhttp

import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.network.CampusIdentity
import com.myleafy.android.core.network.FakeSchoolSessionCookieStore
import com.myleafy.android.core.network.SchoolNetworkError
import com.myleafy.android.core.network.SchoolPortal
import com.myleafy.android.core.network.SchoolSessionState
import com.myleafy.android.parsers.JsoupHtmlParser
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class OkHttpSchoolNetworkClientTest {

    private lateinit var server: MockWebServer
    private lateinit var store: FakeSchoolSessionCookieStore
    private lateinit var session: SchoolSessionState
    private lateinit var client: OkHttpSchoolNetworkClient
    private val identity = CampusIdentity(
        campusId = CampusID.bjfu,
        eduId = "2012345678",
        displayName = null,
        portal = SchoolPortal.UNDERGRADUATE,
        kind = CampusIdentity.IdentityKind.SCHOOL_PORTAL,
    )

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        store = FakeSchoolSessionCookieStore()
        session = SchoolSessionState()
        session.identity = identity
        client = OkHttpSchoolNetworkClient(
            cookieStore = store,
            sessionState = session,
            baseUrl = server.url("/").toString(),
            graduateBaseUrl = null,
            parser = JsoupHtmlParser(),
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun sendsCookieHeaderSortedByCookieName() {
        store.save(
            mapOf("JSESSIONID" to "abc", "Auth" to "1", "Campus" to "bjfu"),
            identity.scopeKey,
            identity.portal.rawValue,
        )
        server.enqueue(MockResponse().setResponseCode(200))

        client.execute(client.requestBuilder("/test").get().build()).use { }

        val recorded = server.takeRequest(5, TimeUnit.SECONDS)
        assertNotNull(recorded)
        assertEquals("Auth=1; Campus=bjfu; JSESSIONID=abc", recorded?.getHeader("Cookie"))
    }
    @Test fun malformedCreditSummaryKeepsValidRankingsAndReportsFailure() = runBlocking {
        server.enqueue(MockResponse().setBody("""<p>学分积为 271.5，班级排名第 8 名，专业排名第 20 名，专业总人数 120 人。</p><table><tr><th>所得学分</th><th>必修学分</th></tr><tr><td>140</td><td>无法识别</td></tr></table>"""))
        val result = client.fetchGradeSupplemental()
        assertTrue(result.rankings.isNotEmpty())
        assertNull(result.summary)
        assertTrue(result.failures.single().contains("官方汇总解析失败"))
    }

    @Test
    fun sendsUserAgentAndNoCacheHeaders() {
        server.enqueue(MockResponse().setResponseCode(200))

        client.execute(client.requestBuilder("/test").get().build()).use { }

        val recorded = server.takeRequest(5, TimeUnit.SECONDS)
        assertEquals(SchoolRequests.USER_AGENT, recorded?.getHeader("User-Agent"))
        assertEquals("no-cache", recorded?.getHeader("Cache-Control"))
        assertEquals("no-cache", recorded?.getHeader("Pragma"))
    }

    @Test
    fun withoutIdentityNoCookieHeaderIsSent() {
        val anonymousClient = OkHttpSchoolNetworkClient(
            cookieStore = store,
            sessionState = SchoolSessionState(),
            baseUrl = server.url("/").toString(),
            graduateBaseUrl = null,
            parser = JsoupHtmlParser(),
        )
        server.enqueue(MockResponse().setResponseCode(200))

        anonymousClient.execute(anonymousClient.requestBuilder("/test").get().build()).use { }

        val recorded = server.takeRequest(5, TimeUnit.SECONDS)
        assertNull(recorded?.getHeader("Cookie"))
    }

    @Test
    fun persistsSetCookieFromResponse() {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .addHeader("Set-Cookie", "JSESSIONID=ABC123; Path=/; HttpOnly")
                .addHeader("Set-Cookie", "Campus=bjfu; Path=/"),
        )

        client.execute(client.requestBuilder("/test").get().build()).use { }

        val stored = store.load(identity.scopeKey, identity.portal.rawValue)
        assertEquals(mapOf("JSESSIONID" to "ABC123", "Campus" to "bjfu"), stored)
    }

    @Test
    fun cookiesReflectsStoreAndClearSessionDeletes() {
        store.save(mapOf("Auth" to "1"), identity.scopeKey, identity.portal.rawValue)
        assertEquals(mapOf("Auth" to "1"), client.cookies)

        client.clearSession()
        assertEquals(emptyMap<String, String>(), client.cookies)
    }

    @Test
    fun unimplementedBusinessMethodsFailFast() {
        assertThrows(NotImplementedError::class.java) {
            runBlocking { client.fetchGraduatePublicKey() }
        }
        assertThrows(NotImplementedError::class.java) {
            runBlocking { client.loginGraduate("account", "password", "captcha") }
        }
    }

    @Test
    fun fetchTimetableParsesRecords() {
        val html = "<input name='xnxq01id' value='2025-2026-2'>" + fixture("timetable_kbcontent_div.html")
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path?.startsWith("/jsxsd/xskb/xskb_list.do") == true ->
                    MockResponse().setBody(html)
                else -> MockResponse().setResponseCode(404)
            }
        }

        val records = runBlocking { client.fetchTimetable("2025-2026-2") }
        assertEquals(2, records.size)
        assertEquals("森林生态学", records.first { it.courseName == "森林生态学" }.courseName)
        assertEquals(3, records.first { it.courseName == "数据结构" }.dayOfWeek)
    }

    @Test
    fun timetableFollowsSchoolPostFormAndRejectsThePreviouslySelectedSemester() {
        val requested = "2025-2026-2"
        val initial = """<form method="post" action="/jsxsd/xskb/current.do">
            <input name="token" value="school-value"><select name="xnxq01id">
            <option selected value="2025-2026-1">上学期</option>
            <option value="$requested">本学期</option></select></form>""" + fixture("timetable_kbcontent_div.html")
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path?.startsWith("/jsxsd/xskb/xskb_list.do") == true -> MockResponse().setBody(initial)
                request.path == "/jsxsd/xskb/current.do" && request.method == "POST" -> {
                    val body = request.body.readUtf8()
                    assertTrue(body.contains("token=school-value"))
                    assertTrue(body.contains("xnxq01id=$requested"))
                    MockResponse().setBody("<input name='xnxq01id' value='$requested'>" + fixture("timetable_kbcontent_div.html"))
                }
                else -> MockResponse().setResponseCode(404)
            }
        }
        val stages = mutableListOf<com.myleafy.android.core.network.AcademicStage>()
        val records = runBlocking { client.fetchTimetable(requested, stages::add) }
        assertEquals(2, records.size)
        assertTrue(stages.contains(com.myleafy.android.core.network.AcademicStage.PROCESSING_TIMETABLE))
    }

    @Test
    fun fetchTimetableThrowsSessionExpiredOnLoginPage() {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path?.startsWith("/jsxsd/xskb/xskb_list.do") == true ->
                    MockResponse().setBody("<html>验证码</html>")
                request.path == "/jsxsd/framework/xsMain.jsp" -> MockResponse().setBody("<html>验证码</html>")
                else -> MockResponse().setResponseCode(404)
            }
        }

        assertThrows(SchoolNetworkError.SessionExpired::class.java) {
            runBlocking { client.fetchTimetable("2025-2026-2") }
        }
    }

    @Test
    fun fetchGradesParsesRecords() {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path?.startsWith("/jsxsd/kscj/cjcx_list") == true ->
                    MockResponse().setBody(fixture("grades_with_rows.html"))
                else -> MockResponse().setResponseCode(404)
            }
        }

        val grades = runBlocking { client.fetchGrades() }
        assertEquals(2, grades.size)
        assertEquals("数据结构", grades[0].courseName)
        assertEquals("92", grades[0].score)
    }

    @Test
    fun fetchExamsPostsSemesterAndParsesRecords() {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path?.startsWith("/jsxsd/xsks/xsksap_list") == true ->
                    MockResponse().setBody(fixture("exams_backend_shape.html"))
                else -> MockResponse().setResponseCode(404)
            }
        }

        val exams = runBlocking { client.fetchExams("2025-2026-2") }
        assertEquals(1, exams.size)
        assertEquals("数据结构", exams[0].name)
        assertEquals("2026-06-20", exams[0].date)

        val recorded = server.takeRequest(5, TimeUnit.SECONDS)
        assertEquals("POST", recorded?.method)
        val body = recorded?.body?.readUtf8() ?: ""
        assertTrue(body.contains("xnxqid=2025-2026-2"))
        assertTrue(body.contains("xqlbmc="))
        assertTrue(body.contains("xqlb="))
    }

    @Test
    fun fetchGradesThrowsSessionExpiredOnLoginPage() {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path?.startsWith("/jsxsd/kscj/cjcx_list") == true ->
                    MockResponse().setBody("<html>验证码</html>")
                else -> MockResponse().setResponseCode(404)
            }
        }

        assertThrows(SchoolNetworkError.SessionExpired::class.java) {
            runBlocking { client.fetchGrades() }
        }
    }

    @Test
    fun fetchEmptyClassroomsParsesRooms() {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path?.startsWith("/jsxsd/kbxx/jsjy_query2") == true ->
                    MockResponse().setBody(requireNotNull(javaClass.getResource("/school/classroom-day-matrix.html")).readText())
                else -> MockResponse().setResponseCode(404)
            }
        }

        val rooms = runBlocking { client.fetchEmptyClassrooms("2025-2026-2", week = 1, day = 1, startPeriod = 1, endPeriod = 12) }
        assertEquals(3, rooms.size)
        assertEquals("学研A座", rooms[0].building)
        assertEquals("0304", rooms[0].room)

        val recorded = server.takeRequest(5, TimeUnit.SECONDS)
        assertEquals("POST", recorded?.method)
        val body = recorded?.body?.readUtf8().orEmpty()
        assertTrue(body.contains("zc=1"))
        assertTrue(body.contains("zc2=1"))
        assertTrue(body.contains("xq=1"))
        assertTrue(body.contains("jc=01"))
        assertTrue(body.contains("jc2=12"))
        assertTrue(body.contains("xnxqh=2025-2026-2"))
    }

    private fun fixture(name: String): String {
        val stream = checkNotNull(javaClass.classLoader?.getResourceAsStream("jwxt/fixtures/$name")) {
            "Fixture 缺失: jwxt/fixtures/$name"
        }
        return stream.bufferedReader().readText()
    }
}
