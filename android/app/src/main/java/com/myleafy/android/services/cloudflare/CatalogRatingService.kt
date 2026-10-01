package com.myleafy.android.services.cloudflare

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

enum class RatingCatalogKind(val route: String) {
    TEACHER("teachers"),
    COURSE("courses"),
    DISH("dishes"),
}

@Serializable
data class RatingCatalogItemDto(
    val id: Long,
    val name: String,
    val unit: String? = null,
    val category: String? = null,
    val credit: Double? = null,
    val location: String? = null,
    val rating_average: Double = 0.0,
    val rating_count: Int = 0,
    val rating_1_count: Int = 0,
    val rating_2_count: Int = 0,
    val rating_3_count: Int = 0,
    val rating_4_count: Int = 0,
    val rating_5_count: Int = 0,
    val viewer_rating: UserCatalogRatingDto? = null,
)

@Serializable
data class UserCatalogRatingDto(
    val teacher_id: Long? = null,
    val course_id: Long? = null,
    val dish_id: Long? = null,
    val user_id: String,
    val stars: Int,
) {
    fun itemId(kind: RatingCatalogKind): Long? = when (kind) {
        RatingCatalogKind.TEACHER -> teacher_id
        RatingCatalogKind.COURSE -> course_id
        RatingCatalogKind.DISH -> dish_id
    }
}

@Serializable
data class CatalogSuggestionInsert(
    val suggestion_type: String,
    val user_id: String,
    val name: String,
    val unit: String,
    val teacher_name: String? = null,
    val category: String? = null,
    val credit: Double? = null,
    val initial_stars: Int?,
    val note: String? = null,
)

class CatalogRatingService(private val client: BackendClient) {
    suspend fun fetchCatalog(kind: RatingCatalogKind, search: String, filterValue: String?, offset: Int, limit: Int, canteen: String? = null): List<RatingCatalogItemDto> =
        client.request("/v1/catalog/${kind.route}", query = mapOf("search" to search.trim(), "filter_value" to filterValue,
            "canteen" to canteen, "offset" to offset.coerceAtLeast(0).toString(), "limit" to limit.coerceIn(1, 50).toString()))
    suspend fun fetchMyRatings(kind: RatingCatalogKind, profileId: String): List<UserCatalogRatingDto> =
        client.request("/v1/catalog/${kind.route}/ratings")
    suspend fun submitRating(kind: RatingCatalogKind, itemId: Long, profileId: String, stars: Int): RatingCatalogItemDto {
        require(stars in 1..5) { "评分必须在 1 到 5 星之间" }
        return client.request("/v1/catalog/${kind.route}/$itemId/rating", "PUT", body = buildJsonObject { put("stars", stars) })
    }
    suspend fun submitSuggestion(insert: CatalogSuggestionInsert) {
        require(insert.name.isNotBlank()) { "名称不能为空" }
        client.requestText("/v1/catalog/suggestions", "POST", client.json.encodeToJsonElement(insert))
    }
}
