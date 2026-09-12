package com.myleafy.android.services.cloudflare

import com.myleafy.android.services.supabase.*
import com.myleafy.android.shared.model.FeedQuery
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class CloudflareServicesTest {
    private val postId = "10000000-0000-4000-8000-000000000001"
    private val profileId = "10000000-0000-4000-8000-000000000002"
    private val memberId = "10000000-0000-4000-8000-000000000003"
    private val requests = mutableListOf<Request>()
    private fun client(respond: (Request) -> String): MyLeafyBackendClient {
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            requests.add(request)
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).message("test").code(200)
                .body(respond(request).toResponseBody("application/json".toMediaType())).build()
        }.build()
        return MyLeafyBackendClient("https://api.test.invalid", object : BackendSessionStore {
            override fun load() = BackendSession("signed-test", profileId, true)
            override fun save(session: BackendSession) = Unit
            override fun clear() = Unit
        }, http)
    }
    private fun Request.payload(): JsonObject {
        val buffer = okio.Buffer(); body!!.writeTo(buffer)
        return Json.parseToJsonElement(buffer.readUtf8()).jsonObject
    }

    @Test fun reactionPatchKeepsFullPostAndSetsServerState() = runBlocking {
        val service = CloudflareCommunityService(client { request ->
            if (request.method == "GET") """{"id":"$postId","author_id":"$profileId","title":"标题","body":"正文","viewer_has_liked":true,"like_count":8}"""
            else """{"post_id":"$postId","like_count":7,"viewer_has_liked":false}"""
        })
        val result = service.togglePostLike(postId)
        assertEquals("正文", result.body); assertEquals(7, result.like_count); assertFalse(result.viewer_has_liked)
        assertEquals("DELETE", requests.last().method)
    }

    @Test fun postCreationKeepsStableIdsAndExplicitNullCategory() = runBlocking {
        val service = CloudflareCommunityService(client { """{"id":"$postId","author_id":"$profileId","title":"标题","body":"正文"}""" })
        service.createPost(postId, memberId, "标题", "正文", null, false)
        service.createPost(postId, memberId, "标题", "正文", null, false)
        assertEquals(requests[0].payload(), requests[1].payload())
        assertEquals(memberId, requests[0].payload().getValue("request_id").jsonPrimitive.content)
        assertEquals(JsonNull, requests[0].payload()["category"])
    }

    @Test fun reportsUseTargetIdAndServerOwnsActor() = runBlocking {
        CloudflareCommunityService(client { "{}" }).reportComment(memberId, "其他", null)
        val payload = requests.single().payload()
        assertEquals(memberId, payload.getValue("target_id").jsonPrimitive.content)
        assertEquals("comment", payload.getValue("target_type").jsonPrimitive.content)
        assertFalse(payload.containsKey("reported_user_id"))
    }

    @Test fun catalogFiltersAreSentBeforePagination() = runBlocking {
        CloudflareCatalogRatingService(client { "[]" }).fetchCatalog(RatingCatalogKind.DISH, " 米饭 ", "第一食堂", 50, 20)
        val url = requests.single().url
        assertEquals("/v1/catalog/dishes", url.encodedPath)
        assertEquals("第一食堂", url.queryParameter("filter_value")); assertEquals("50", url.queryParameter("offset"))
    }

    @Test fun leavingResolvesIncomingMemberIdWithoutChangingOwner() = runBlocking {
        val service = CloudflareTimetableSharingService(client { request ->
            if (request.method == "GET") """[{"id":"$memberId","owner_id":"$postId","viewer_id":"$profileId","created_at":"now","updated_at":"now"}]""" else "{}"
        })
        service.leave(postId)
        assertEquals("incoming", requests.first().url.queryParameter("direction"))
        assertEquals("/v1/timetables/members/$memberId/leave", requests.last().url.encodedPath)
    }

    @Test fun malformedFeedFailsInsteadOfBecomingEmpty() = runBlocking {
        val service = CloudflareCommunityService(client { "{}" })
        try { service.fetchFeed(FeedQuery(campus_id = "bjfu")); fail("Missing posts must fail") }
        catch (_: IllegalStateException) { }
    }

    @Test fun threadPageKeepsDeletedRootAndVisibleReply() = runBlocking {
        val service = CloudflareCommunityService(client { """{"comments":[{"thread_root_id":"$postId","id":"$postId","post_id":"$memberId","author_id":"$profileId","is_deleted_placeholder":true},{"thread_root_id":"$postId","id":"$memberId","post_id":"$memberId","author_id":"$profileId","parent_comment_id":"$postId","body":"回复"}],"has_more":true}""" })
        val result = service.fetchCommentThreads(memberId)
        assertTrue(result.has_more); assertTrue(result.comments.first().is_deleted_placeholder)
        assertEquals("回复", result.comments.last().body)
        assertEquals("/v1/community/posts/$memberId/comment-threads", requests.single().url.encodedPath)
    }
}
