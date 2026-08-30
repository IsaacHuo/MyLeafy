package com.myleafy.android.features.profile

import com.myleafy.android.core.network.SchoolSessionState
import com.myleafy.android.services.supabase.CommunityService
import com.myleafy.android.shared.model.ProfileDto

/**
 * “我的”仓储：社区资料（Supabase 权威）+ 本地身份。
 */
interface ProfileRepository {
    /** 占位实现标识：true 时 UI 提示社区资料未接入。 */
    val isPlaceholder: Boolean

    /** 按学校身份引导/继承社区资料；未登录或无配置返回 null。 */
    suspend fun fetchProfile(): ProfileDto?

    suspend fun updateProfile(nickname: String, bio: String?, major: String?, grade: String?): ProfileDto
}

/**
 * 线上实现：学校登录后调用 community-bootstrap-user 按
 * (edu_id, campus_id) 引导/继承社区 profile。
 */
class LiveProfileRepository(
    private val serviceProvider: () -> CommunityService?,
    private val sessionState: SchoolSessionState,
    private val onProfileUpdated: (ProfileDto) -> Unit = {},
) : ProfileRepository {

    override val isPlaceholder: Boolean = false

    override suspend fun fetchProfile(): ProfileDto? {
        val identity = sessionState.identity ?: return null
        val resolved = serviceProvider() ?: return null
        val result = resolved.bootstrapCommunityUser(
            eduId = identity.eduId,
            displayName = identity.displayName ?: identity.eduId,
            campusId = identity.campusId.rawValue,
        )
        return result.profile
    }

    override suspend fun updateProfile(
        nickname: String,
        bio: String?,
        major: String?,
        grade: String?,
    ): ProfileDto {
        val identity = sessionState.identity ?: error("请先登录学校账号")
        val service = serviceProvider() ?: error("当前身份不可使用社区，或 Supabase 未配置")
        val profile = service.bootstrapCommunityUser(
            eduId = identity.eduId,
            displayName = identity.displayName ?: identity.eduId,
            campusId = identity.campusId.rawValue,
        ).profile
        return service.updateProfile(profile.id, nickname, bio, major, grade)
            .also(onProfileUpdated)
    }
}

/** 占位实现（无 Supabase 配置或未登录时兜底）。 */
class PlaceholderProfileRepository : ProfileRepository {
    override val isPlaceholder: Boolean = true
    override suspend fun fetchProfile(): ProfileDto? = null
    override suspend fun updateProfile(
        nickname: String,
        bio: String?,
        major: String?,
        grade: String?,
    ): ProfileDto = throw NotImplementedError("社区资料未接入")
}
