package com.myleafy.android.services.cloudflare

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test

class CampusCatalogContractTest {
    private fun client(server:MockWebServer)=BackendClient(server.url("/").newBuilder().host("127.0.0.1").build().toString(),object:BackendSessionStore {
        override fun read()="test-session"
        override fun save(token:String)=Unit
        override fun clear()=Unit
    })
    @Test fun catalogUsesServerFiltersViewerRatingAndPostSubmitSummary() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("""[{"id":42,"name":"菜品","unit":"学一食堂","location":"一层","rating_average":4.0,"rating_count":1,"viewer_rating":{"dish_id":42,"user_id":"test","stars":4}}]"""))
            server.enqueue(MockResponse().setBody("""{"id":42,"name":"菜品","rating_average":4.5,"rating_count":2,"rating_5_count":1,"viewer_rating":{"dish_id":42,"user_id":"test","stars":5}}"""))
            val transport=client(server)
            val service=CatalogRatingService(transport)
            val item=service.fetchCatalog(RatingCatalogKind.DISH,"菜","一层",20,20,"学一食堂").single()
            assertEquals(4,item.viewer_rating!!.stars)
            val request=server.takeRequest(); val url=request.requestUrl!!
            assertEquals("20",url.queryParameter("offset")); assertEquals("一层",url.queryParameter("filter_value")); assertEquals("学一食堂",url.queryParameter("canteen"))
            val updated=service.submitRating(RatingCatalogKind.DISH,42,"test",5)
            assertEquals(4.5,updated.rating_average,0.0); assertEquals(2,updated.rating_count); assertEquals(5,updated.viewer_rating!!.stars)
            val submit=server.takeRequest(); assertEquals("PUT",submit.method); assertEquals("/v1/catalog/dishes/42/rating",submit.path)
            transport.close()
        }
    }
    @Test fun feedCursorIsReadAndPassedUnchanged() = runBlocking {
        MockWebServer().use { server ->
            server.start(); server.enqueue(MockResponse().setBody("""{"posts":[],"next_cursor":"opaque+/cursor="}"""))
            val transport=client(server); val service=CommunityService(transport)
            val first=service.fetchFeedPage(com.myleafy.android.shared.model.FeedQuery(campus_id="bjfu"))
            assertEquals("opaque+/cursor=",first.next_cursor)
            server.takeRequest();server.enqueue(MockResponse().setBody("""{"posts":[],"next_cursor":null}"""))
            assertNull(service.fetchFeedPage(com.myleafy.android.shared.model.FeedQuery(campus_id="bjfu",cursor=first.next_cursor)).next_cursor)
            assertEquals(first.next_cursor,server.takeRequest().requestUrl!!.queryParameter("cursor"))
            transport.close()
        }
    }
}
