package com.myleafy.android.services.cloudflare
import java.time.Instant
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.CancellationException
import org.junit.Assert.*
import org.junit.Test
class ForegroundActivityTest {
    private val now = Instant.parse("2026-10-13T08:00:00Z")
    private fun event(id: String, time: Instant = now) = ForegroundActivityEvent(id, time.toString(), "android", "test")
    @Test fun prunesOnlyExpiredEventsAndAcknowledgesMatchingIDs() {
        val queue = ForegroundActivityQueue(events = listOf(event("old", now.minusSeconds(8 * 86400)), event("recent", now.minusSeconds(6 * 86400))))
        assertEquals(listOf("recent"), queue.prune(now).events.map { it.id })
        assertEquals(1, queue.prune(now).acknowledge(setOf("other")).events.size)
        assertTrue(queue.prune(now).acknowledge(setOf("recent")).events.isEmpty())
    }
    @Test fun recreatedProfileClearsFormerEvents() {
        val queue = ForegroundActivityQueue("old-profile", listOf(event("event")))
        assertEquals(1, queue.bind("old-profile").events.size)
        assertTrue(queue.bind("new-profile").events.isEmpty())
    }
    @Test fun guestOrChangedScopeDoesNotReadStorageOrUpload() = runTest {
        val recorder = ForegroundActivityRecorder(read = { error("Guest must not read") }, write = { _, _ -> error("Guest must not write") }, profile = { error("Guest must not bootstrap") }, upload = { _, _ -> error("Guest must not upload") }, isScopeActive = { false }, version = "test")
        try { recorder.record("guest"); fail("Expected cancellation") } catch (_: CancellationException) { }
    }
    @Test fun failedUploadPersistsAndRetriesOriginalEventWithoutDuplicates() = runTest {
        val stored = mutableMapOf<String,String>(); var offline = true; val uploaded = mutableSetOf<String>()
        val recorder = ForegroundActivityRecorder(read = stored::get, write = { key,value -> stored[key] = value }, profile = { "profile" }, upload = { _,events -> if(offline) error("offline"); uploaded.addAll(events.map { it.id }); events.map { it.id }.toSet() }, isScopeActive = { true }, version = "test", now = { now })
        try { recorder.record("student"); fail("Expected offline failure") } catch (_: IllegalStateException) { }
        assertTrue(stored.getValue("foreground-activity:student").contains("occurredAt"))
        offline = false; recorder.record("student")
        assertEquals(2, uploaded.size)
        assertFalse(stored.getValue("foreground-activity:student").contains("occurredAt"))
    }
}
