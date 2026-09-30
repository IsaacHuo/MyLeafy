package com.myleafy.android.features.profile

import com.myleafy.android.core.network.SchoolSessionState
import com.myleafy.android.services.cloudflare.CommunityService
import com.myleafy.android.shared.model.ProfileDto

/**
 * “我的”仓储：社区资料（Cloudflare 权威）+ 本地身份。
 */
interface ProfileRepository {

    /** 按学校身份引导/继承社区资料；未登录或无社区 capability返回 null。 */
    suspend fun fetchProfile(): ProfileDto?

    suspend fun updateProfile(nickname: String, bio: String?, major: String?, grade: String?): ProfileDto
}

/**
 * 线上实现：学校登录后调用 /v1/profile/bootstrap 按
 * (edu_id, campus_id) 引导/继承社区 profile。
 */
class LiveProfileRepository(
    private val serviceProvider: () -> CommunityService?,
    private val sessionState: SchoolSessionState,
    private val onProfileUpdated: (ProfileDto) -> Unit = {},
) : ProfileRepository {


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
        val service = serviceProvider() ?: error("当前身份不可使用社区，请稍后重试")
        val profile = service.bootstrapCommunityUser(
            eduId = identity.eduId,
            displayName = identity.displayName ?: identity.eduId,
            campusId = identity.campusId.rawValue,
        ).profile
        return service.updateProfile(profile.id, nickname, bio, major, grade)
            .also(onProfileUpdated)
    }
}
