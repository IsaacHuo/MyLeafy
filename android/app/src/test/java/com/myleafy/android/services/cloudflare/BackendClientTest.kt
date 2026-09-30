package com.myleafy.android.services.cloudflare

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.*
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.TimeUnit

class BackendClientTest {
    private class Store : BackendSessionStore {
        var token: String? = null
        override fun read() = token
        override fun save(token: String) { this.token = token }
        override fun clear() { token = null }
    }
    @Test fun `one session is established for concurrent callers and profile clears use explicit null`() = runBlocking {
        val server = MockWebServer()
        server.start()
        try {
            server.enqueue(MockResponse().setHeader("set-auth-token", "signed-token").setBody("{\"user\":{\"id\":\"id\"}}"))
            server.enqueue(MockResponse().setBody("{\"id\":\"profile\"}"))
            val store = Store()
            val client = BackendClient(server.url("/").newBuilder().host("127.0.0.1").build().toString(), store)
            assertEquals(0, server.requestCount)
            coroutineScope { List(8) { async { client.establishSession() } }.awaitAll() }
            assertEquals(1, server.requestCount)
            CommunityService(client).updateProfile("profile", "同学", "", null, "2026")
            assertEquals("/v1/auth/sign-in/anonymous", server.takeRequest().path)
            val edit = server.takeRequest()
            assertEquals("PATCH", edit.method)
            assertEquals("Bearer signed-token", edit.getHeader("Authorization"))
            val body = Json.parseToJsonElement(edit.body.readUtf8()).jsonObject
            assertEquals(JsonNull, body["bio"])
            assertEquals(JsonNull, body["major"])
            assertFalse(body.containsKey("is_profile_complete"))
            client.close()
            assertNull(store.token)
        } finally { server.shutdown() }
    }

    @Test fun `failure preserves structured error and does not retry against another authority`() = runBlocking {
        val server = MockWebServer(); server.start()
        try {
            val store = Store().apply { token = "existing" }
            val client = BackendClient(server.url("/").newBuilder().host("127.0.0.1").build().toString(), store)
            server.enqueue(MockResponse().setResponseCode(401).setHeader("X-Request-ID", "trace")
                .setBody("{\"errorEnvelope\":{\"code\":\"unauthenticated\",\"message\":\"请重新登录。\"}}"))
            val failure = runCatching { client.requestText("/v1/profile") }.exceptionOrNull() as BackendError
            assertEquals("unauthenticated", failure.code)
            assertEquals("trace", failure.requestId)
            assertNull(store.token)
            assertEquals(1, server.requestCount)
            client.close()
        } finally { server.shutdown() }
    }

    @Test fun `closing scope cancels response and rejects future requests`() = runBlocking {
        val server = MockWebServer(); server.start()
        try {
            val client = BackendClient(server.url("/").newBuilder().host("127.0.0.1").build().toString(), Store().apply { token = "existing" })
            server.enqueue(MockResponse().setBody("{}").setBodyDelay(2, TimeUnit.SECONDS))
            val operation = async { runCatching { client.requestText("/v1/profile") } }
            withContext(Dispatchers.IO) { assertNotNull(server.takeRequest(2, TimeUnit.SECONDS)) }
            client.close()
            assertTrue(operation.await().isFailure)
            assertTrue(runCatching { client.requestText("/v1/profile") }.exceptionOrNull() is CancellationException)
            assertEquals(1, server.requestCount)
        } finally { server.shutdown() }
    }
    @Test fun `websocket sends scoped authorization and receives change signal`() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().withWebSocketUpgrade(object : okhttp3.WebSocketListener() {
                override fun onOpen(webSocket: okhttp3.WebSocket, response: okhttp3.Response) {
                    webSocket.send("{\"type\":\"changed\",\"event_id\":\"event\"}")
                }
            }))
            val client = BackendClient(server.url("/").newBuilder().host("127.0.0.1").build().toString(), Store().apply { token = "session" })
            withTimeout(5_000) { client.events("feed").first() }
            val request = server.takeRequest()
            assertEquals("/v1/events/feed", request.path)
            assertEquals("Bearer session", request.getHeader("Authorization"))
            client.close()
        }
    }

}
