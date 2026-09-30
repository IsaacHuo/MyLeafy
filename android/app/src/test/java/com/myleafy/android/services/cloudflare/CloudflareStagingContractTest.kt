package com.myleafy.android.services.cloudflare

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.UUID
import okhttp3.OkHttpClient
import okhttp3.Request

/** Explicit opt-in only; fixed staging authority, disposable identities and account cleanup. */
class CloudflareStagingContractTest {
    private class Store : BackendSessionStore {
        var token: String? = null
        override fun read() = token
        override fun save(token: String) { this.token = token }
        override fun clear() { token = null }
    }
    @Test fun profileMediaNotificationsRatingsAndSharingMatchDeployedStaging() = runBlocking {
        assumeTrue(System.getProperty("cloudflareStagingCheck") == "true")
        val origin = "https://api-staging.myleafy.space"
        val health = OkHttpClient().newCall(Request.Builder().url("$origin/health").build()).execute().use {
            assertTrue(it.isSuccessful)
            Json.parseToJsonElement(it.body!!.string()).jsonObject
        }
        assertEquals("staging", health.getValue("environment").jsonPrimitive.content)
        val owner = BackendClient(origin, Store())
        val viewer = BackendClient(origin, Store())
        var ownerCreated = false
        var viewerCreated = false
        try {
            val first = CommunityService(owner)
            val second = CommunityService(viewer)
            val ownerProfile = first.bootstrapCommunityUser("android-contract-${UUID.randomUUID()}", "Android契约验证", "bjfu").profile
            ownerCreated = true
            val viewerProfile = second.bootstrapCommunityUser("android-contract-${UUID.randomUUID()}", "Android权限验证", "bjfu").profile
            viewerCreated = true
            first.updateProfile(ownerProfile.id, "Android契约验证", "测试", "测试", "2026")
            val cleared = first.updateProfile(ownerProfile.id, "Android契约验证", null, null, null)
            assertNull(cleared.bio); assertNull(cleared.major); assertNull(cleared.grade)
            second.updateProfile(viewerProfile.id, "Android权限验证", null, null, null)
            first.acceptTerms(); second.acceptTerms()
            assertTrue(first.hasAcceptedTerms())
            val postId = UUID.randomUUID().toString()
            val requestId = UUID.randomUUID().toString()
            first.createPost(postId, requestId, "Android隔离契约测试", "此内容仅用于隔离环境自动回归，测试后删除。", null, false, imageCount = 1)
            val retry = first.createPost(postId, requestId, "Android隔离契约测试", "此内容仅用于隔离环境自动回归，测试后删除。", null, false, imageCount = 1)
            assertEquals(postId, retry.id)
            val imageId = UUID.randomUUID().toString()
            val bytes = requireNotNull(javaClass.classLoader!!.getResourceAsStream("media/contract.jpg")).use { it.readBytes() }
            first.uploadPostImage(ownerProfile.id, postId, imageId, bytes, bytes, 0)
            first.uploadPostImage(ownerProfile.id, postId, imageId, bytes, bytes, 0)
            val attached = first.fetchPost(postId)!!.images.single()
            assertTrue(attached.full_url?.startsWith("https://") == true)
            second.createComment(UUID.randomUUID().toString(), UUID.randomUUID().toString(), postId, "隔离环境回复验证", null, null)
            assertTrue(first.unreadNotificationCount() > 0)
            first.fetchNotifications(ownerProfile.id).filter { !it.is_read }.forEach { first.markNotificationRead(it.id) }
            val teachers = first.catalogRatings.fetchCatalog(RatingCatalogKind.TEACHER, "", null, 0, 1)
            if (teachers.isNotEmpty()) {
                first.catalogRatings.submitRating(RatingCatalogKind.TEACHER, teachers.first().id, ownerProfile.id, 4)
                assertEquals(4, first.catalogRatings.fetchMyRatings(RatingCatalogKind.TEACHER, ownerProfile.id).first().stars)
            }
            val term = "2026-2027-1"
            val sharing = first.timetableSharing
            sharing.publish("bjfu", ownerProfile.id, term, listOf(SharedTimetableCourseDto(UUID.randomUUID().toString(), "测试课程", "", "测试教室", "", 1, listOf(1), listOf(1, 2))))
            assertTrue(second.timetableSharing.viewableSnapshots("bjfu", viewerProfile.id, term).none { it.owner_id == ownerProfile.id })
            val invitation = sharing.createInvite()
            assertEquals(ownerProfile.id, second.timetableSharing.accept(invitation.code!!).owner_id)
            assertEquals(ownerProfile.id, second.timetableSharing.viewableSnapshots("bjfu", viewerProfile.id, term).single { it.owner_id == ownerProfile.id }.owner_id)
            sharing.revoke(ownerProfile.id, viewerProfile.id)
            assertTrue(second.timetableSharing.viewableSnapshots("bjfu", viewerProfile.id, term).none { it.owner_id == ownerProfile.id })
            sharing.stopSharing()
        } finally {
            try { if (viewerCreated) viewer.requestText("/v1/account", "DELETE") }
            finally {
                try { if (ownerCreated) owner.requestText("/v1/account", "DELETE") }
                finally { viewer.close(); owner.close() }
            }
        }
    }
}
