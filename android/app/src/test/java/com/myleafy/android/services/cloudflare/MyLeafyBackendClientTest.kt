package com.myleafy.android.services.cloudflare

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.io.IOException
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

    @Test fun signOutClearsLocalSessionEvenWhenRevocationFails() = runBlocking {
        val store = MemoryStore().apply { value = BackendSession("signed", "ba74d3b9-c806-4fca-8bfc-1e5b60dd8d10", true) }
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).message("maintenance").code(503)
                .body("""{"errorEnvelope":{"code":"maintenance","message":"维护中"}}""".toResponseBody("application/json".toMediaType())).build()
        }.build()
        val client = MyLeafyBackendClient("https://api.test.invalid", store, http)
        try { client.signOut(); fail("Revocation failure must remain visible") }
        catch (error: BackendException) { assertEquals("maintenance", error.code) }
        assertNull(store.value); assertNull(client.userId)
    }

    @Test fun uploadUsesBinaryBodyAndDownloadKeepsPathInQuery() = runBlocking {
        val store = MemoryStore().apply { value = BackendSession("signed", "ba74d3b9-c806-4fca-8bfc-1e5b60dd8d10", true) }
        val bytes = byteArrayOf(0, 1, -1, 8)
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            assertEquals("Bearer signed", request.header("Authorization"))
            val payload = if (request.method == "POST") {
                val buffer = okio.Buffer(); request.body!!.writeTo(buffer)
                assertArrayEquals(bytes, buffer.readByteArray())
                assertEquals("application/pdf", request.body!!.contentType().toString())
                assertEquals("attachment", request.url.queryParameter("kind"))
                "{}".toByteArray()
            } else {
                assertEquals("posts/中文 文件.pdf", request.url.queryParameter("path"))
                bytes
            }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).message("test").code(200)
                .body(payload.toResponseBody()).build()
        }.build()
        val client = MyLeafyBackendClient("https://api.test.invalid", store, http)
        client.upload(bytes, "application/pdf", mapOf("kind" to "attachment"))
        assertArrayEquals(bytes, client.download("community-attachments", "posts/中文 文件.pdf"))
    }

    @Test fun signalSubscriptionWithoutSessionFailsBeforeConnecting() = runBlocking {
        val client = MyLeafyBackendClient("https://api.test.invalid", MemoryStore())
        try { client.changes(BackendSignalScope.FEED).collect { fail("No signal expected") }; fail("Missing session must fail") }
        catch (error: BackendException) { assertEquals(401, error.status) }
    }

    @Test fun cancellingRequestCancelsUnderlyingOkHttpCall() = runBlocking {
        val started = CountDownLatch(1)
        val cancelled = CountDownLatch(1)
        val store = MemoryStore().apply { value = BackendSession("signed", "ba74d3b9-c806-4fca-8bfc-1e5b60dd8d10", true) }
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            started.countDown()
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (!chain.call().isCanceled() && System.nanoTime() < deadline) Thread.sleep(5)
            if (chain.call().isCanceled()) cancelled.countDown()
            throw IOException("cancelled")
        }.build()
        val client = MyLeafyBackendClient("https://api.test.invalid", store, http)
        val job = launch(Dispatchers.Default) { client.request("/v1/profile") }
        assertTrue(withContext(Dispatchers.IO) { started.await(5, TimeUnit.SECONDS) })
        job.cancelAndJoin()
        assertTrue(withContext(Dispatchers.IO) { cancelled.await(5, TimeUnit.SECONDS) })
    }

    private class MemoryStore : BackendSessionStore {
        var value: BackendSession? = null
        override fun load() = value
        override fun save(session: BackendSession) { value = session }
        override fun clear() { value = null }
    }
}
