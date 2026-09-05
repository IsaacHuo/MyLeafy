package com.myleafy.android.services.cloudflare

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class MyLeafyBackendClientTest {
    @Test fun rejectsPlainHttpOrigin() {
        assertThrows(IllegalArgumentException::class.java) {
            MyLeafyBackendClient("http://api.test.invalid", MemoryStore())
        }
    }

    @Test fun usesSignedHeaderAndPreservesSessionOnMaintenance() = runBlocking {
        val store = MemoryStore()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            val response = Response.Builder().request(request).protocol(Protocol.HTTP_1_1).message("test")
                .header("Content-Type", "application/json")
            when (request.url.encodedPath) {
                "/v1/auth/sign-in/anonymous" -> response.code(200).header("set-auth-token", "signed-session.test")
                    .body("""{"token":"unsigned-must-not-be-used","user":{"id":"ba74d3b9-c806-4fca-8bfc-1e5b60dd8d10","isAnonymous":true}}""".toResponseBody("application/json".toMediaType()))
                "/v1/maintenance" -> response.code(503).header("X-Request-ID", "test-request")
                    .body("""{"errorEnvelope":{"code":"maintenance","message":"维护中"}}""".toResponseBody("application/json".toMediaType()))
                else -> response.code(200).body("""{"authorization":"${request.header("Authorization")}"}""".toResponseBody("application/json".toMediaType()))
            }.build()
        }.build()
        val client = MyLeafyBackendClient("https://api.test.invalid", store, http)
        client.ensureAnonymousSession()
        assertEquals("Bearer signed-session.test", client.request("/v1/echo").jsonObject.getValue("authorization").jsonPrimitive.content)
        try {
            client.request("/v1/maintenance")
            fail("Expected maintenance rejection")
        } catch (error: BackendException) {
            assertEquals(503, error.status)
            assertEquals("maintenance", error.code)
            assertEquals("test-request", error.requestId)
        }
        assertNotNull(store.value)
        client.signOut(localOnly = true)
        assertNull(store.value)
    }

    private class MemoryStore : BackendSessionStore {
        var value: BackendSession? = null
        override fun load() = value
        override fun save(session: BackendSession) { value = session }
        override fun clear() { value = null }
    }
}
