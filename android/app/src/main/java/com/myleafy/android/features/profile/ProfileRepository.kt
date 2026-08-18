package com.myleafy.android.features.profile

import com.myleafy.android.shared.model.ProfileDto

/**
 * “我的”仓储：社区资料与本地身份。
 * 社区资料以 Supabase 为权威（阶段 4）；本地身份来自 SettingsStore。
 */
interface ProfileRepository {
    /** 占位实现标识：true 时 UI 提示社区资料未接入。 */
    val isPlaceholder: Boolean

    val profile: ProfileDto?
}

class PlaceholderProfileRepository : ProfileRepository {
    override val isPlaceholder: Boolean = true
    override val profile: ProfileDto? = null
}
