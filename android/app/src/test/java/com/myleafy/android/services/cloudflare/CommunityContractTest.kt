package com.myleafy.android.services.cloudflare

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test

class CommunityContractTest {
    private fun client(server: MockWebServer) = BackendClient(server.url("/").newBuilder().host("127.0.0.1").build().toString(),
        object : BackendSessionStore {
            override fun read() = "test-session"
            override fun save(token: String) = Unit
            override fun clear() = Unit
        })

    @Test fun attachedImageRetryDoesNotUploadAgain() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("""{"id":"post","author_id":"author","title":"标题","body":"正文","status":"published","images":[{"id":"image","full_url":"https://media.example/full","thumbnail_url":"https://media.example/thumb"}]}"""))
            val transport = client(server)
            CommunityService(transport).uploadPostImage("author", "post", "image", byteArrayOf(1), byteArrayOf(2), 0)
            assertEquals(1, server.requestCount)
            assertEquals("/v1/community/posts/post", server.takeRequest().path)
            transport.close()
        }
    }

    @Test fun notificationCountIncludesReadableAnnouncementsAndUsesCorrectReadRoute() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("[]"))
            server.enqueue(MockResponse().setBody("""[{"id":"notice","title":"公告","body":"全文","read_at":null,"created_at":"2026-09-29"}]"""))
            server.enqueue(MockResponse().setBody("{\"updated\":true}"))
            val transport = client(server)
            val service = CommunityService(transport)
            val notification = service.fetchNotifications("profile").single()
            assertFalse(notification.is_read)
            assertEquals("全文", notification.body)
            service.markNotificationRead(notification.id)
            server.takeRequest(); server.takeRequest()
            assertEquals("/v1/announcements/notice/read", server.takeRequest().path)
            transport.close()
        }
    }

    @Test fun revokeUsesRelationshipIdAndDoesNotSendOwnerOrViewerAsActor() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("""[{"id":"relation","owner_id":"owner","viewer_id":"viewer","created_at":"","updated_at":""}]"""))
            server.enqueue(MockResponse().setBody("{\"revoked\":true}"))
            val transport = client(server)
            TimetableSharingService(transport).revoke("owner", "viewer")
            server.takeRequest()
            val revoke = server.takeRequest()
            assertEquals("DELETE", revoke.method)
            assertEquals("/v1/timetables/members/relation", revoke.path)
            assertFalse(revoke.body.readUtf8().contains("owner"))
            transport.close()
        }
    }
}
