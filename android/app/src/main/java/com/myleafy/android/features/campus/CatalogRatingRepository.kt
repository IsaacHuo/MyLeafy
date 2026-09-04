package com.myleafy.android.features.campus

import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.campus.CampusCapabilities
import com.myleafy.android.features.community.CommunityRepository
import com.myleafy.android.services.supabase.CatalogRatingService
import com.myleafy.android.services.supabase.CatalogSuggestionInsert
import com.myleafy.android.services.supabase.RatingCatalogItemDto
import com.myleafy.android.services.supabase.RatingCatalogKind

data class CatalogRatingItem(
    val profile: RatingCatalogItemDto,
    val myStars: Int?,
)

class CatalogRatingRepository(
    private val serviceProvider: () -> CatalogRatingService?,
    private val communityRepository: CommunityRepository,
    private val scopeStore: ActiveAppScopeStore,
) {
    val isAvailable: Boolean
        get() = scopeStore.current.supports(CampusCapabilities.COMMUNITY) &&
            scopeStore.current.supports(CampusCapabilities.CATALOG_RATINGS)

    suspend fun page(
        kind: RatingCatalogKind,
        search: String,
        filterValue: String?,
        offset: Int,
        limit: Int = 20,
    ): List<CatalogRatingItem> {
        require(isAvailable) { "当前身份或校园暂不支持评价服务" }
        val profile = requireCompleteProfile()
        val service = requireNotNull(serviceProvider()) { "评价服务未配置" }
        val ratings = service.fetchMyRatings(kind, profile.id).associateBy { it.itemId(kind) }
        return service.fetchCatalog(kind, search, filterValue, offset, limit).map { item ->
            CatalogRatingItem(item, ratings[item.id]?.stars)
        }
    }

    suspend fun rate(kind: RatingCatalogKind, itemId: Long, stars: Int) {
        require(isAvailable) { "当前身份或校园暂不支持评价服务" }
        val profile = requireCompleteProfile()
        requireNotNull(serviceProvider()) { "评价服务未配置" }
            .submitRating(kind, itemId, profile.id, stars)
    }

    suspend fun suggest(
        kind: RatingCatalogKind,
        name: String,
        unit: String,
        teacherName: String?,
        category: String?,
        credit: Double?,
        stars: Int,
        note: String?,
    ) {
        require(isAvailable) { "当前身份或校园暂不支持评价服务" }
        val profile = requireCompleteProfile()
        require(name.isNotBlank()) { "名称不能为空" }
        require(unit.isNotBlank()) { "学院、单位或食堂不能为空" }
        if (kind == RatingCatalogKind.COURSE) require(!teacherName.isNullOrBlank()) { "课程建议需要填写授课教师" }
        require(credit == null || credit >= 0) { "学分不能小于 0" }
        requireNotNull(serviceProvider()) { "评价服务未配置" }.submitSuggestion(
            CatalogSuggestionInsert(
                suggestion_type = kind.name.lowercase(),
                user_id = profile.id,
                name = name.trim(),
                unit = unit.trim(),
                teacher_name = teacherName?.trim()?.takeIf(String::isNotEmpty),
                category = category?.trim()?.takeIf(String::isNotEmpty),
                credit = credit,
                initial_stars = stars,
                note = note?.trim()?.takeIf(String::isNotEmpty),
            ),
        )
    }

    private suspend fun requireCompleteProfile() = communityRepository.currentProfile().also {
        require(it.is_profile_complete && it.nickname.isNotBlank()) { "请先在“我的”中完善社区资料" }
    }
}
