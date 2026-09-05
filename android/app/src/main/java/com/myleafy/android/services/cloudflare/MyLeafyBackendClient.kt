package com.myleafy.android.services.cloudflare

import com.myleafy.android.core.security.SecureStorage
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

@Serializable
data class BackendSession(val token: String, val userId: String, val anonymous: Boolean)

interface BackendSessionStore {
    fun load(): BackendSession?
    fun save(session: BackendSession)
    fun clear()
}

class KeystoreBackendSessionStore(
    private val secure: SecureStorage,
    origin: String,
) : BackendSessionStore {
    private val key = "cloudflare-session:$origin"
    private val json = Json { ignoreUnknownKeys = true }

    override fun load(): BackendSession? {
        val raw = secure.read(key)
        if (raw == null && secure.has(key)) throw IOException("无法读取已保存的登录状态，请重新登录。")
        return raw?.let { json.decodeFromString<BackendSession>(it) }
    }

    override fun save(session: BackendSession) = secure.save(key, json.encodeToString(session))
    override fun clear() = secure.remove(key)
}

class BackendException(val status: Int, val code: String, override val message: String, val requestId: String?) : IOException(message)

/** Created only for an enabled online identity. No network I/O occurs in the constructor. */
class MyLeafyBackendClient(
    origin: String,
    private val store: BackendSessionStore,
    private val http: OkHttpClient = OkHttpClient.Builder()
        .callTimeout(30, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .build(),
) {
    private val originUrl = origin.toHttpUrl().also {
        require(it.isHttps && it.username.isEmpty() && it.password.isEmpty() && it.encodedPath == "/" && it.query == null && it.fragment == null) {
            "Backend origin must be an HTTPS origin without credentials, path or query."
        }
    }
    private val json = Json { ignoreUnknownKeys = true }
    private val sessionMutex = Mutex()
    @Volatile private var session: BackendSession? = store.load()
    val userId: String? get() = session?.userId

    suspend fun ensureAnonymousSession() = sessionMutex.withLock {
        if (session != null) return@withLock
        val response = execute("/v1/auth/sign-in/anonymous", "POST", "{}".toByteArray(), authenticated = false)
        captureSession(response)
    }

    suspend fun signIn(email: String, password: String): String = sessionMutex.withLock {
        val body = buildJsonObject { put("email", email); put("password", password) }
        captureSession(execute("/v1/auth/sign-in/email", "POST", body.toString().toByteArray(), authenticated = false))
        checkNotNull(session).userId
    }

    suspend fun exchangeLegacySession(accessToken: String, anonymous: Boolean): String = sessionMutex.withLock {
        val body = buildJsonObject { put("access_token", accessToken) }
        val response = execute("/v1/session/exchange", "POST", body.toString().toByteArray(), authenticated = false)
        val value = json.parseToJsonElement(response.bytes.decodeToString()).jsonObject
        val id = UUID.fromString(value.getValue("user_id").jsonPrimitive.content).toString()
        persist(BackendSession(value.getValue("token").jsonPrimitive.content, id, anonymous))
        id
    }

    suspend fun signOut(localOnly: Boolean = false) = sessionMutex.withLock {
        if (!localOnly && session != null) execute("/v1/auth/sign-out", "POST", "{}".toByteArray())
        store.clear()
        session = null
    }

    suspend fun request(path: String, method: String = "GET", body: JsonElement? = null, query: Map<String, String> = emptyMap()): JsonElement {
        val response = execute(path, method, body?.toString()?.toByteArray(), query = query)
        return json.parseToJsonElement(response.bytes.decodeToString())
    }

    suspend fun upload(bytes: ByteArray, contentType: String, query: Map<String, String>): JsonElement {
        val response = execute("/v1/files/upload", "POST", bytes, contentType = contentType, query = query)
        return json.parseToJsonElement(response.bytes.decodeToString())
    }

    suspend fun download(bucket: String, path: String): ByteArray =
        execute("/v1/files/read", "GET", query = mapOf("bucket" to bucket, "path" to path)).bytes

    private suspend fun execute(
        path: String,
        method: String,
        bytes: ByteArray? = null,
        contentType: String = "application/json",
        query: Map<String, String> = emptyMap(),
        authenticated: Boolean = true,
    ): BackendResponse = withContext(Dispatchers.IO) {
        require(path.startsWith("/v1/")) { "Invalid versioned API path" }
        val url = originUrl.newBuilder().encodedPath(path).apply {
            query.forEach { (key, value) -> addQueryParameter(key, value) }
        }.build()
        val request = Request.Builder().url(url).header("Accept", "application/json")
            .header("Cache-Control", "no-store")
        if (authenticated) {
            val active = session ?: throw BackendException(401, "unauthenticated", "请重新登录。", null)
            request.header("Authorization", "Bearer ${active.token}")
        }
        val body = bytes?.toRequestBody(contentType.toMediaType())
            ?: if (method in listOf("POST", "PUT", "PATCH")) ByteArray(0).toRequestBody(contentType.toMediaType()) else null
        http.newCall(request.method(method, body).build()).execute().use { response ->
            val data = response.body?.bytes() ?: ByteArray(0)
            if (!response.isSuccessful) {
                val error = runCatching { json.parseToJsonElement(data.decodeToString()).jsonObject }.getOrNull()
                val envelope = error?.get("errorEnvelope")?.jsonObject
                throw BackendException(
                    response.code,
                    envelope?.get("code")?.jsonPrimitive?.content ?: error?.get("code")?.jsonPrimitive?.content ?: "http_${response.code}",
                    envelope?.get("message")?.jsonPrimitive?.content ?: error?.get("error")?.jsonPrimitive?.content ?: error?.get("message")?.jsonPrimitive?.content ?: "后台请求失败，请稍后重试。",
                    response.header("X-Request-ID"),
                )
            }
            BackendResponse(data, response.header("set-auth-token"))
        }
    }

    private fun captureSession(response: BackendResponse) {
        val token = response.signedToken?.takeIf(String::isNotBlank)
            ?: throw BackendException(0, "missing_signed_session", "登录状态未建立，请重试。", null)
        val user = json.parseToJsonElement(response.bytes.decodeToString()).jsonObject.getValue("user").jsonObject
        val id = UUID.fromString(user.getValue("id").jsonPrimitive.content).toString()
        persist(BackendSession(token, id, user["isAnonymous"]?.jsonPrimitive?.content == "true"))
    }

    private fun persist(value: BackendSession) {
        store.save(value)
        session = value
    }

    private data class BackendResponse(val bytes: ByteArray, val signedToken: String?)
}
