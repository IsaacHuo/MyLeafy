package com.myleafy.android.features.campus

import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.campus.CampusCapabilities
import com.myleafy.android.features.community.CommunityRepository
import com.myleafy.android.services.cloudflare.CatalogRatingService
import com.myleafy.android.services.cloudflare.CatalogSuggestionInsert
import com.myleafy.android.services.cloudflare.RatingCatalogItemDto
import com.myleafy.android.services.cloudflare.RatingCatalogKind

data class CatalogRatingItem(
    val profile: RatingCatalogItemDto,
    val myStars: Int?,
    val localTeachers: List<String> = emptyList(),
)

class CatalogRatingRepository(
    private val serviceProvider: () -> CatalogRatingService?,
    private val communityRepository: CommunityRepository,
    private val scopeStore: ActiveAppScopeStore,
    private val localCourses: suspend () -> List<com.myleafy.android.core.data.local.CourseEntity> = { emptyList() },
) {
    val scopeKeys = scopeStore.scope
    val currentScopeKey get() = scopeStore.current.scopeKey
    val isAvailable: Boolean
        get() = scopeStore.current.supports(CampusCapabilities.COMMUNITY) &&
            scopeStore.current.supports(CampusCapabilities.CATALOG_RATINGS)

    suspend fun page(
        kind: RatingCatalogKind,
        search: String,
        filterValue: String?,
        offset: Int,
        limit: Int = 20,
        canteen: String? = null,
    ): List<CatalogRatingItem> {
        require(isAvailable) { "当前身份或校园暂不支持评价服务" }
        val scope = currentScopeKey
        requireCompleteProfile()
        val service = requireNotNull(serviceProvider()) { "评价服务未配置" }
        val courses = if (kind == RatingCatalogKind.COURSE) localCourses() else emptyList()
        val result = service.fetchCatalog(kind, search, filterValue, offset, limit, canteen).map { item ->
            CatalogRatingItem(item, item.viewer_rating?.stars, courses.filter { it.courseName.trim() == item.name.trim() }.map { it.teacher }.filter(String::isNotBlank).distinct())
        }
        if (scope != currentScopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
        return result
    }

    suspend fun rate(kind: RatingCatalogKind, itemId: Long, stars: Int): CatalogRatingItem {
        require(isAvailable) { "当前身份或校园暂不支持评价服务" }
        val scope = currentScopeKey
        val profile = requireCompleteProfile()
        if (scope != currentScopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
        val result = requireNotNull(serviceProvider()) { "评价服务未配置" }
            .submitRating(kind, itemId, profile.id, stars)
        if (scope != currentScopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
        return CatalogRatingItem(result, result.viewer_rating?.stars)
    }

    suspend fun suggest(
        kind: RatingCatalogKind,
        name: String,
        unit: String,
        teacherName: String?,
        category: String?,
        credit: Double?,
        stars: Int?,
        note: String?,
    ) {
        require(isAvailable) { "当前身份或校园暂不支持评价服务" }
        val scope = currentScopeKey
        val profile = requireCompleteProfile()
        if (scope != currentScopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
        require(name.isNotBlank()) { "名称不能为空" }
        require(unit.isNotBlank()) { "学院、单位或食堂不能为空" }
        if (kind == RatingCatalogKind.COURSE) require(!teacherName.isNullOrBlank()) { "课程建议需要填写授课教师" }
        require(credit == null || credit.isFinite() && credit in 0.0..999.9) { "学分须为 0–999.9 的有限数值" }
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
        if (scope != currentScopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
    }

    private suspend fun requireCompleteProfile() = communityRepository.currentProfile().also {
        require(it.is_profile_complete && it.nickname.isNotBlank()) { "请先在“我的”中完善社区资料" }
    }
}
