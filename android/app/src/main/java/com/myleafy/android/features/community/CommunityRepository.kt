package com.myleafy.android.features.community

/**
 * 社区仓储接口。Supabase 为权威来源（RLS + campus 作用域），
 * 阶段 2 由 supabase-kt 实现，阶段 1 仅为占位。
 */
interface CommunityRepository {
    val isAvailable: Boolean
}

class PlaceholderCommunityRepository : CommunityRepository {
    override val isAvailable: Boolean = true
}
