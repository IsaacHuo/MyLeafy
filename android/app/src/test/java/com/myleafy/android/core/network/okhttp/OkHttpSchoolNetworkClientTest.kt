package com.myleafy.android.core.network.okhttp

import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.network.CampusIdentity
import com.myleafy.android.core.network.FakeSchoolSessionCookieStore
import com.myleafy.android.core.network.SchoolPortal
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test

class OkHttpSchoolNetworkClientTest {

    private lateinit var server: MockWebServer
    private lateinit var store: FakeSchoolSessionCookieStore
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
        client = OkHttpSchoolNetworkClient(
            cookieStore = store,
            identityProvider = { identity },
            baseUrl = server.url("/").toString(),
            graduateBaseUrl = null,
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
            identityProvider = { null },
            baseUrl = server.url("/").toString(),
            graduateBaseUrl = null,
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
            runBlocking { client.loginUndergraduate("account", "password", "captcha") }
        }
        assertThrows(NotImplementedError::class.java) {
            runBlocking { client.fetchTimetable("2025-2026-2").first() }
        }
    }
}
