package com.myleafy.android.services.cloudflare

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID

@Serializable
data class ForegroundActivityEvent(val id: String, val occurredAt: String, val platform: String, val appVersion: String)

@Serializable
data class ForegroundActivityQueue(val profileID: String? = null, val events: List<ForegroundActivityEvent> = emptyList()) {
    fun prune(now: Instant) = copy(events = events.filter {
        val time = Instant.parse(it.occurredAt)
        !time.isBefore(now.minusSeconds(7 * 86400)) && !time.isAfter(now.plusSeconds(300))
    })
    fun bind(profile: String) = copy(profileID = profile, events = if (profileID != null && profileID != profile) emptyList() else events)
    fun acknowledge(ids: Set<String>) = copy(events = events.filterNot { it.id in ids })
}

/** MainActivity's RESUMED lifecycle owns execution. No internal scope or background producer. */
class ForegroundActivityRecorder(
    private val read: (String) -> String?,
    private val write: (String, String) -> Unit,
    private val profile: suspend () -> String,
    private val upload: suspend (String, List<ForegroundActivityEvent>) -> Set<String>,
    private val isScopeActive: (String) -> Boolean,
    private val version: String,
    private val now: () -> Instant = { Instant.now() },
) {
    private val mutex = Mutex()
    suspend fun record(scope: String) = mutex.withLock {
        currentCoroutineContext().ensureActive()
        if (!isScopeActive(scope)) throw CancellationException("Activity identity changed")
        val key = "foreground-activity:$scope"
        var queue = read(key)?.let { Json.decodeFromString<ForegroundActivityQueue>(it) } ?: ForegroundActivityQueue()
        queue = queue.prune(now())
        val event = ForegroundActivityEvent(UUID.randomUUID().toString(), now().toString(), "android", version)
        queue = queue.copy(events = queue.events + event)
        write(key, Json.encodeToString(ForegroundActivityQueue.serializer(), queue))
        val profileID = profile()
        currentCoroutineContext().ensureActive()
        if (!isScopeActive(scope)) throw CancellationException("Activity identity changed")
        queue = queue.bind(profileID)
        if (queue.events.none { it.id == event.id }) queue = queue.copy(events = queue.events + event)
        write(key, Json.encodeToString(ForegroundActivityQueue.serializer(), queue))
        while (queue.events.isNotEmpty()) {
            currentCoroutineContext().ensureActive()
            if (!isScopeActive(scope)) throw CancellationException("Activity identity changed")
            val receipt = upload(profileID, queue.events.take(100))
            currentCoroutineContext().ensureActive()
            val next = queue.acknowledge(receipt)
            check(next.events.size < queue.events.size) { "Activity receipt did not acknowledge this batch" }
            queue = next
            write(key, Json.encodeToString(ForegroundActivityQueue.serializer(), queue))
        }
    }
}
