package com.myleafy.android.services.supabase

import kotlinx.serialization.Serializable

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


@Serializable
data class SharedTimetableCourseDto(
    val id: String,
    val course_name: String,
    val teacher: String,
    val room: String,
    val location: String,
    val day_of_week: Int,
    val weeks: List<Int>,
    val duration: List<Int>,
)

@Serializable
data class SharedTimetableSnapshotDto(
    val id: String,
    val owner_id: String,
    val semester_id: String,
    val courses: List<SharedTimetableCourseDto>,
    val course_count: Int,
    val published_at: String,
    val created_at: String,
    val updated_at: String,
)

@Serializable
data class TimetableShareMemberDto(
    val id: String,
    val owner_id: String,
    val viewer_id: String,
    val created_at: String,
    val updated_at: String,
    val revoked_at: String? = null,
)

@Serializable
data class TimetableInviteDto(
    val id: String,
    val owner_id: String,
    val semester_id: String,
    val expires_at: String,
    val accepted_by: String? = null,
    val accepted_at: String? = null,
    val created_at: String,
    val code: String? = null,
)

