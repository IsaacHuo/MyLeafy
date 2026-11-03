package com.myleafy.android.core.network.okhttp

import com.myleafy.android.core.network.FakeSchoolSessionCookieStore
import com.myleafy.android.core.network.SchoolNetworkError
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
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import kotlinx.serialization.json.*
import java.net.URLDecoder

class SchoolAuthFlowTest {

    private lateinit var server: MockWebServer
    private lateinit var store: FakeSchoolSessionCookieStore
    private lateinit var session: SchoolSessionState
    private lateinit var client: OkHttpSchoolNetworkClient

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        store = FakeSchoolSessionCookieStore()
        session = SchoolSessionState()
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
    fun announcementDoesNotBlockVerifiedCandidateSession() = runBlocking {
        val delegate = authenticDispatcher()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse =
                if (request.path == "/Logon.do?method=logon") {
                    MockResponse().addHeader("Set-Cookie", "JSESSIONID=xyz; Path=/").setBody(loginMessageFixture("announcement"))
                } else delegate.dispatch(request)
        }
        client.loginUndergraduate(client.prepareUndergraduateChallenge(), "2012", " Ab9+%&#=Z7 ", "1234")
        assertTrue(session.isLoggedIn)
        server.takeRequest(5, TimeUnit.SECONDS)
        server.takeRequest(5, TimeUnit.SECONDS)
        val body = checkNotNull(server.takeRequest(5, TimeUnit.SECONDS)).body.readUtf8()
        val encoded = URLDecoder.decode(body.substringAfter("encoded=").substringBefore("&"), "UTF-8")
        assertEquals(com.myleafy.android.core.network.SchoolLoginEncoder.encodeKey("SECRETCODE#12345", "2012", " Ab9+%&#=Z7 "), encoded)
    }

    @Test
    fun laterCaptchaErrorIsNotReplacedByAnnouncement() = runBlocking {
        val delegate = authenticDispatcher()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse =
                if (request.path == "/Logon.do?method=logon") {
                    MockResponse().setBody(loginMessageFixture("captcha_after_validation"))
                } else delegate.dispatch(request)
        }
        val error = assertThrows(SchoolNetworkError.LoginFailed::class.java) {
            runBlocking { client.loginUndergraduate(client.prepareUndergraduateChallenge(), "2012", "pw", "0000") }
        }
        assertEquals("验证码错误", error.message)
        assertEquals(false, session.isLoggedIn)
        assertEquals(3, server.requestCount)
    }

    @Test
    fun invalidKeyStopsBeforeCaptchaAndLogin() = runBlocking {
        server.enqueue(MockResponse().setBody("no"))
        assertThrows(SchoolNetworkError.Unexpected::class.java) {
            runBlocking { client.prepareUndergraduateChallenge() }
        }
        assertEquals(1, server.requestCount)
        assertEquals(false, session.isLoggedIn)
    }

    @Test
    fun unknownPageAtStudentUrlCannotConfirmLogin() = runBlocking {
        val delegate = authenticDispatcher()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse =
                if (request.path == "/jsxsd/framework/xsMain.jsp") MockResponse().setBody("<html>学校维护中</html>")
                else delegate.dispatch(request)
        }
        assertThrows(SchoolNetworkError.LoginFailed::class.java) {
            runBlocking { client.loginUndergraduate(client.prepareUndergraduateChallenge(), "2012", "pw", "1234") }
        }
        assertEquals(false, session.isLoggedIn)
        assertEquals(emptyMap<String, String>(), client.cookies)
    }

    private fun loginMessageFixture(name: String): String {
        val raw = checkNotNull(javaClass.classLoader?.getResourceAsStream("jwxt/fixtures/login_messages.json"))
            .bufferedReader().use { it.readText() }
        return Json.parseToJsonElement(raw).jsonArray.first {
            it.jsonObject.getValue("name").jsonPrimitive.content == name
        }.jsonObject.getValue("html").jsonPrimitive.content
    }

    @Test
    fun loginSucceedsPersistsCookiesAndMarksSession() = runBlocking {
        server.dispatcher = authenticDispatcher()

        client.loginUndergraduate(client.prepareUndergraduateChallenge(), "2012", "pw", "1234")

        assertTrue(session.isLoggedIn)
        assertEquals("2012", session.identity?.eduId)
        val identity = checkNotNull(session.identity)
        assertEquals(mapOf("JSESSIONID" to "xyz"), store.load(identity.scopeKey, identity.portal.rawValue))
        assertEquals(mapOf("JSESSIONID" to "xyz"), client.cookies)

        // One challenge: key → captcha → login → verify, no second key request.
        val keyRequest = server.takeRequest(5, TimeUnit.SECONDS)
        val captchaRequest = server.takeRequest(5, TimeUnit.SECONDS)
        val loginRequest = server.takeRequest(5, TimeUnit.SECONDS)
        val verifyRequest = server.takeRequest(5, TimeUnit.SECONDS)
        assertEquals("/Logon.do?method=logon&flag=sess", keyRequest?.path)
        assertEquals("/jsxsd/framework/xsMain.jsp", verifyRequest?.path)
        assertEquals("JSESSIONID=xyz", verifyRequest?.getHeader("Cookie"))

        // 登录 POST 携带 encoded 与验证码
        assertTrue(loginRequest?.path?.startsWith("/Logon.do?method=logon") == true)
        val body = loginRequest?.body?.readUtf8() ?: ""
        assertTrue(body.contains("RANDOMCODE=1234"))
        assertTrue(body.contains("encoded="))
        assertTrue(body.startsWith("useDogCode="))

        assertNotNull(keyRequest)
    }

    @Test
    fun loginFailsOnCaptchaMessageAndClearsState() = runBlocking {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path == "/Logon.do?method=logon&flag=sess" ->
                    MockResponse().setBody("SECRETCODE#12345")
                request.path == "/verifycode.servlet" -> MockResponse().setBody("CAPTCHA-IMG")
                request.path == "/Logon.do?method=logon" ->
                    MockResponse().setBody("""<script>alert('验证码错误')</script>""")
                else -> MockResponse().setResponseCode(404)
            }
        }

        val error = assertThrows(SchoolNetworkError.LoginFailed::class.java) {
            runBlocking { client.loginUndergraduate(client.prepareUndergraduateChallenge(), "2012", "pw", "0000") }
        }
        assertEquals("验证码错误", error.message)
        assertEquals(false, session.isLoggedIn)
        assertEquals(null, session.identity)
    }

    @Test
    fun loginFailsWhenSessionVerifyUnsuccessful() = runBlocking {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path == "/Logon.do?method=logon&flag=sess" ->
                    MockResponse().setBody("SECRETCODE#12345")
                request.path == "/verifycode.servlet" -> MockResponse().setBody("CAPTCHA-IMG")
                request.path == "/Logon.do?method=logon" ->
                    MockResponse().setResponseCode(200)
                        .addHeader("Set-Cookie", "JSESSIONID=xyz; Path=/")
                        .setBody("<html>退出系统</html>")
                // 会话验证返回登录页 → 判定失败
                request.path == "/jsxsd/framework/xsMain.jsp" ->
                    MockResponse().setBody("<html>验证码</html>")
                else -> MockResponse().setResponseCode(404)
            }
        }

        assertThrows(SchoolNetworkError.LoginFailed::class.java) {
            runBlocking { client.loginUndergraduate(client.prepareUndergraduateChallenge(), "2012", "pw", "1234") }
        }
        assertEquals(false, session.isLoggedIn)
        assertEquals(null, session.identity)
        // 登录期间写入的 Cookie 应被清理
        assertEquals(emptyMap<String, String>(), client.cookies)
    }

    @Test
    fun fetchUndergraduateCaptchaReturnsBytes() = runBlocking {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path == "/Logon.do?method=logon&flag=sess" ->
                    MockResponse()
                        .addHeader("Set-Cookie", "JSESSIONID=pre-auth; Path=/; HttpOnly")
                        .setBody("SECRETCODE#12345")
                request.path == "/verifycode.servlet" ->
                    MockResponse().setBody("CAPTCHA-IMG")
                else -> MockResponse().setResponseCode(404)
            }
        }

        val bytes = client.prepareUndergraduateChallenge().imageBytes
        assertEquals("CAPTCHA-IMG", String(bytes))
        val keyRequest = server.takeRequest(5, TimeUnit.SECONDS)
        val captchaRequest = server.takeRequest(5, TimeUnit.SECONDS)
        assertNotNull(keyRequest)
        assertEquals("JSESSIONID=pre-auth", captchaRequest?.getHeader("Cookie"))
    }

    @Test
    fun loginReusesCaptchaSessionCookie() = runBlocking {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path == "/Logon.do?method=logon&flag=sess" ->
                    MockResponse()
                        .addHeader("Set-Cookie", "JSESSIONID=pre-auth; Path=/; HttpOnly")
                        .setBody("SECRETCODE#12345")
                request.path == "/verifycode.servlet" ->
                    MockResponse().setBody("CAPTCHA-IMG")
                request.path == "/Logon.do?method=logon" ->
                    MockResponse().setBody("<html>退出系统</html>")
                request.path == "/jsxsd/framework/xsMain.jsp" ->
                    MockResponse().setBody("<html>学生课表</html>")
                else -> MockResponse().setResponseCode(404)
            }
        }

        val challenge = client.prepareUndergraduateChallenge()
        client.loginUndergraduate(challenge, "2012", "pw", "1234")

        server.takeRequest(5, TimeUnit.SECONDS)
        val captchaRequest = server.takeRequest(5, TimeUnit.SECONDS)
        val loginRequest = server.takeRequest(5, TimeUnit.SECONDS)
        assertEquals("JSESSIONID=pre-auth", captchaRequest?.getHeader("Cookie"))
        assertEquals("JSESSIONID=pre-auth", loginRequest?.getHeader("Cookie"))
        assertTrue(session.isLoggedIn)
        val identity = checkNotNull(session.identity)
        assertEquals(
            mapOf("JSESSIONID" to "pre-auth"),
            store.load(identity.scopeKey, identity.portal.rawValue),
        )
    }

    private fun authenticDispatcher(): Dispatcher = object : Dispatcher() {
        override fun dispatch(request: RecordedRequest): MockResponse = when {
            request.path == "/Logon.do?method=logon&flag=sess" ->
                MockResponse().setBody("SECRETCODE#12345")
            request.path == "/verifycode.servlet" ->
                MockResponse().setBody("CAPTCHA-IMG")
            request.path == "/Logon.do?method=logon" ->
                MockResponse().setResponseCode(200)
                    .addHeader("Set-Cookie", "JSESSIONID=xyz; Path=/; HttpOnly")
                    .setBody("<html>退出系统</html>")
            request.path == "/jsxsd/framework/xsMain.jsp" ->
                MockResponse().setResponseCode(200).setBody("<html>学生课表</html>")
            else -> MockResponse().setResponseCode(404)
        }
    }
}
