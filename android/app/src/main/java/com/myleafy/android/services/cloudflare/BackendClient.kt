package com.myleafy.android.services.cloudflare

import com.myleafy.android.core.security.SecureStorage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

interface BackendSessionStore {
    fun read(): String?
    fun save(token: String)
    fun clear()
}

class SecureBackendSessionStore(private val storage: SecureStorage, origin: String, scope: String) : BackendSessionStore {
    private val key = "cloudflare:$origin:$scope"
    override fun read() = storage.read(key)
    override fun save(token: String) = storage.save(key, token)
    override fun clear() = storage.remove(key)
}

class BackendError(val status: Int, val code: String, message: String, val requestId: String?) : IOException(message)

/** One immutable backend authority and school scope per client; closing invalidates all in-flight work. */
class BackendClient(
    origin: String,
    private val store: BackendSessionStore,
    private val isScopeActive: () -> Boolean = { true },
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS)
        .callTimeout(90, TimeUnit.SECONDS).followRedirects(false).build(),
) {
    val json = Json { ignoreUnknownKeys = true }
    private val base = origin.toHttpUrl().also {
        require((it.isHttps || it.host == "localhost" || it.host == "127.0.0.1") &&
            it.encodedPath == "/" && it.query == null && it.username.isEmpty() && it.password.isEmpty())
    }
    private val sessionMutex = Mutex()
    private val lock = Any()
    private var token: String? = store.read()
    private var closed = false
    private val sockets = mutableSetOf<WebSocket>()
    val hasSession: Boolean get() = synchronized(lock) { !closed && token != null && isScopeActive() }

    suspend fun establishSession() = sessionMutex.withLock {
        synchronized(lock) { checkOpen(); if (token != null) return@withLock }
        val response = execute("/v1/auth/sign-in/anonymous", "POST", body = "{}".toRequestBody(JSON), authenticated = false)
        val signedToken = response.token?.takeIf(String::isNotBlank)
            ?: throw BackendError(0, "missing_session", "无法建立登录状态，请重试。", null)
        synchronized(lock) { checkOpen(); store.save(signedToken); token = signedToken }
    }

    suspend inline fun <reified T> request(
        path: String, method: String = "GET", body: JsonElement? = null,
        query: Map<String, String?> = emptyMap(),
    ): T = json.decodeFromString(requestText(path, method, body, query))

    suspend fun requestText(path: String, method: String = "GET", body: JsonElement? = null,
        query: Map<String, String?> = emptyMap()): String {
        val requestBody = if (method in listOf("GET", "HEAD")) null else (body?.toString() ?: "{}").toRequestBody(JSON)
        return execute(path, method, query, requestBody).body
    }

    suspend fun upload(postId: String, imageId: String, kind: String, bytes: ByteArray): String {
        val response = execute("/v1/files/upload", "POST",
            mapOf("post_id" to postId, "upload_id" to imageId, "kind" to kind, "name" to "$imageId.jpg"),
            bytes.toRequestBody("image/jpeg".toMediaType()))
        return json.parseToJsonElement(response.body).jsonObject.getValue("path").jsonPrimitive.content
    }

    suspend fun signOut() {
        try { if (synchronized(lock) { token != null && !closed }) requestText("/v1/auth/sign-out", "POST") }
        finally { close() }
    }

    fun close() {
        synchronized(lock) { closed = true; token = null; store.clear(); sockets.forEach { it.cancel() }; sockets.clear() }
        http.dispatcher.cancelAll()
        http.connectionPool.evictAll()
    }

    private fun checkOpen() { if (closed || !isScopeActive()) throw CancellationException("Identity scope closed") }

    fun events(scope: String) = callbackFlow<Unit> {
        require(scope == "feed" || scope == "notifications")
        val request = synchronized(lock) {
            checkOpen()
            Request.Builder().url(base.newBuilder().encodedPath("/v1/events/$scope").build())
                .header("Authorization", "Bearer ${token ?: throw BackendError(401, "unauthenticated", "请重新登录。", null)}").build()
        }
        val socket = synchronized(lock) {
            checkOpen()
            http.newWebSocket(request, object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    try {
                        synchronized(lock) { checkOpen() }
                        if (json.parseToJsonElement(text).jsonObject["type"]?.jsonPrimitive?.content == "changed") trySend(Unit)
                    } catch (failure: Exception) { close(failure) }
                }
                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { close(t) }
                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(code, reason)
                    close(IOException("Subscription closed ($code)"))
                }
            }).also(sockets::add)
        }
        awaitClose { synchronized(lock) { sockets.remove(socket) }; socket.cancel() }
    }
    private data class Reply(val body: String, val token: String?)

    private suspend fun execute(path: String, method: String, query: Map<String, String?> = emptyMap(),
        body: RequestBody? = null, authenticated: Boolean = true): Reply {
        require(path.startsWith("/v1/") && !path.contains('?') && !path.contains('#'))
        val sentToken = synchronized(lock) {
            checkOpen()
            if (authenticated) token ?: throw BackendError(401, "unauthenticated", "请重新登录。", null) else null
        }
        val url = base.newBuilder().encodedPath(path).apply {
            query.forEach { (key, value) -> if (value != null) addQueryParameter(key, value) }
        }.build()
        val request = Request.Builder().url(url).method(method, body).apply {
            if (sentToken != null) header("Authorization", "Bearer $sentToken")
        }.build()
        val reply = suspendCancellableCoroutine<Reply> { continuation ->
            val call = http.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) { if (continuation.isActive) continuation.resumeWithException(e) }
                override fun onResponse(call: Call, response: Response) {
                    try {
                        response.use {
                            val text = it.body?.string().orEmpty()
                            synchronized(lock) {
                                checkOpen()
                                if (authenticated && token != sentToken) throw CancellationException("Session changed")
                                if (it.code == 401 && authenticated) { token = null; store.clear() }
                            }
                            if (!it.isSuccessful) {
                                val root = runCatching { json.parseToJsonElement(text).jsonObject }.getOrNull()
                                val envelope = root?.get("errorEnvelope") as? JsonObject
                                throw BackendError(it.code,
                                    envelope?.get("code")?.jsonPrimitive?.content ?: "http_${it.code}",
                                    envelope?.get("message")?.jsonPrimitive?.content
                                        ?: (root?.get("message") as? JsonPrimitive)?.content
                                        ?: (root?.get("error") as? JsonPrimitive)?.content ?: "后台请求失败，请稍后重试。",
                                    it.header("X-Request-ID"))
                            }
                            if (continuation.isActive) continuation.resume(Reply(text, it.header("set-auth-token")))
                        }
                    } catch (failure: Exception) { if (continuation.isActive) continuation.resumeWithException(failure) }
                }
            })
        }
        synchronized(lock) { checkOpen() }
        return reply
    }

    companion object { private val JSON = "application/json".toMediaType() }
}
