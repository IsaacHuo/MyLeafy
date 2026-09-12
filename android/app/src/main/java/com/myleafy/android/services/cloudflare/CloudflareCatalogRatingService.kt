package com.myleafy.android.services.cloudflare

import com.myleafy.android.services.CatalogRatingService
import com.myleafy.android.services.supabase.*
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put

class CloudflareCatalogRatingService(private val client: MyLeafyBackendClient) : CatalogRatingService {
    override suspend fun fetchCatalog(kind: RatingCatalogKind, search: String, filterValue: String?, offset: Int, limit: Int): List<RatingCatalogItemDto> =
        client.decodeRequest("/v1/catalog/${kind.path}", query = buildMap {
            put("search", search.trim()); put("offset", offset.coerceAtLeast(0).toString()); put("limit", limit.coerceIn(1, 50).toString())
            filterValue?.takeIf(String::isNotBlank)?.let { put("filter_value", it) }
        })

    override suspend fun fetchMyRatings(kind: RatingCatalogKind, profileId: String): List<UserCatalogRatingDto> =
        client.decodeRequest("/v1/catalog/${kind.path}/ratings")

    override suspend fun submitRating(kind: RatingCatalogKind, itemId: Long, profileId: String, stars: Int) {
        require(stars in 1..5) { "评分必须在 1 到 5 星之间" }
        require(itemId > 0)
        client.request("/v1/catalog/${kind.path}/$itemId/rating", "PUT", buildJsonObject { put("stars", stars) })
    }

    override suspend fun submitSuggestion(insert: CatalogSuggestionInsert) {
        require(insert.name.isNotBlank()) { "名称不能为空" }
        require(insert.initial_stars in 1..5) { "评分必须在 1 到 5 星之间" }
        client.request("/v1/catalog/suggestions", "POST", backendJson.encodeToJsonElement(insert))
    }

    private val RatingCatalogKind.path: String get() = when (this) {
        RatingCatalogKind.TEACHER -> "teachers"
        RatingCatalogKind.COURSE -> "courses"
        RatingCatalogKind.DISH -> "dishes"
    }
}
