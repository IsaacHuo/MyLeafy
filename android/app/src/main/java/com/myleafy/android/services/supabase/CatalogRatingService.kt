package com.myleafy.android.services.supabase

import com.myleafy.android.services.CatalogRatingService
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.SupabaseClient
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class SupabaseCatalogRatingService(private val client: SupabaseClient) : CatalogRatingService {
    override suspend fun fetchCatalog(
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

    override suspend fun fetchMyRatings(kind: RatingCatalogKind, profileId: String): List<UserCatalogRatingDto> =
        client.postgrest[kind.ratingTable].select {
            filter { eq("user_id", profileId) }
        }.decodeList()

    override suspend fun submitRating(kind: RatingCatalogKind, itemId: Long, profileId: String, stars: Int) {
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

    override suspend fun submitSuggestion(insert: CatalogSuggestionInsert) {
        require(insert.name.isNotBlank()) { "名称不能为空" }
        require(insert.initial_stars in 1..5) { "评分必须在 1 到 5 星之间" }
        client.postgrest["catalog_suggestions"].insert(insert)
    }
}
