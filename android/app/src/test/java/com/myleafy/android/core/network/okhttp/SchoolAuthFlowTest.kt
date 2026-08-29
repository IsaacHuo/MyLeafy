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
    fun loginSucceedsPersistsCookiesAndMarksSession() = runBlocking {
        server.dispatcher = authenticDispatcher()

        client.loginUndergraduate("2012", "pw", "1234")

        assertTrue(session.isLoggedIn)
        assertEquals("2012", session.identity?.eduId)
        val identity = checkNotNull(session.identity)
        assertEquals(mapOf("JSESSIONID" to "xyz"), store.load(identity.scopeKey, identity.portal.rawValue))
        assertEquals(mapOf("JSESSIONID" to "xyz"), client.cookies)

        // 请求顺序：key → 登录 POST → 会话验证
        val keyRequest = server.takeRequest(5, TimeUnit.SECONDS)
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
                request.path == "/Logon.do?method=logon" ->
                    MockResponse().setBody("""<script>alert('验证码错误')</script>""")
                else -> MockResponse().setResponseCode(404)
            }
        }

        val error = assertThrows(SchoolNetworkError.LoginFailed::class.java) {
            runBlocking { client.loginUndergraduate("2012", "pw", "0000") }
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
            runBlocking { client.loginUndergraduate("2012", "pw", "1234") }
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

        val bytes = client.fetchUndergraduateCaptcha()
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

        client.fetchUndergraduateCaptcha()
        client.loginUndergraduate("2012", "pw", "1234")

        server.takeRequest(5, TimeUnit.SECONDS)
        val captchaRequest = server.takeRequest(5, TimeUnit.SECONDS)
        val refreshedKeyRequest = server.takeRequest(5, TimeUnit.SECONDS)
        val loginRequest = server.takeRequest(5, TimeUnit.SECONDS)
        assertEquals("JSESSIONID=pre-auth", captchaRequest?.getHeader("Cookie"))
        assertEquals("JSESSIONID=pre-auth", refreshedKeyRequest?.getHeader("Cookie"))
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
