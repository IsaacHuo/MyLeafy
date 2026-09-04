package com.myleafy.android.services.supabase

import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.SupabaseClient
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

enum class RatingCatalogKind(val catalogTable: String, val ratingTable: String, val idColumn: String) {
    TEACHER("teachers", "teacher_ratings", "teacher_id"),
    COURSE("course_catalog", "course_ratings", "course_id"),
    DISH("dish_catalog", "dish_ratings", "dish_id"),
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
    val initial_stars: Int,
    val note: String? = null,
)

class CatalogRatingService(private val client: SupabaseClient) {
    suspend fun fetchCatalog(
        kind: RatingCatalogKind,
        search: String,
        filterValue: String?,
        offset: Int,
        limit: Int,
    ): List<RatingCatalogItemDto> {
        val normalizedSearch = search.trim().lowercase()
        val safeOffset = offset.coerceAtLeast(0)
        val safeLimit = limit.coerceIn(1, 50)
        return client.postgrest[kind.catalogTable].select {
            filter {
                if (kind != RatingCatalogKind.TEACHER) eq("status", "published")
                if (normalizedSearch.isNotEmpty()) ilike("search_text", "%$normalizedSearch%")
                filterValue?.takeIf(String::isNotBlank)?.let {
                    eq(if (kind == RatingCatalogKind.DISH) "location" else if (kind == RatingCatalogKind.COURSE) "category" else "unit", it)
                }
            }
            order("rating_average", Order.DESCENDING)
            order("rating_count", Order.DESCENDING)
            order("name", Order.ASCENDING)
            range(safeOffset.toLong(), (safeOffset + safeLimit - 1).toLong())
        }.decodeList()
    }

    suspend fun fetchMyRatings(kind: RatingCatalogKind, profileId: String): List<UserCatalogRatingDto> =
        client.postgrest[kind.ratingTable].select {
            filter { eq("user_id", profileId) }
        }.decodeList()

    suspend fun submitRating(kind: RatingCatalogKind, itemId: Long, profileId: String, stars: Int) {
        require(stars in 1..5) { "评分必须在 1 到 5 星之间" }
        val payload = buildJsonObject {
            put(kind.idColumn, itemId)
            put("user_id", profileId)
            put("stars", stars)
        }
        runCatching {
            client.postgrest[kind.ratingTable].insert(payload)
        }.getOrElse {
            client.postgrest[kind.ratingTable].update({ set("stars", stars) }) {
                filter {
                    eq(kind.idColumn, itemId)
                    eq("user_id", profileId)
                }
            }
        }
    }

    suspend fun submitSuggestion(insert: CatalogSuggestionInsert) {
        require(insert.name.isNotBlank()) { "名称不能为空" }
        require(insert.initial_stars in 1..5) { "评分必须在 1 到 5 星之间" }
        client.postgrest["catalog_suggestions"].insert(insert)
    }
}
