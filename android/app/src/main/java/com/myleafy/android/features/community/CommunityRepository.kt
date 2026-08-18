package com.myleafy.android.features.community

import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.PostDto
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/**
 * 社区仓储接口。Supabase 为权威来源（RLS + campus 作用域）。
 * 阶段 4 由 supabase-kt 实现；阶段 1.5 为占位（UI 如实展示“未接入”）。
 */
interface CommunityRepository {
    val isAvailable: Boolean

    /** 占位实现标识：true 时 UI 提示功能未接入，避免误导。 */
    val isPlaceholder: Boolean

    fun feed(query: FeedQuery): Flow<List<PostDto>>
}

class PlaceholderCommunityRepository : CommunityRepository {
    override val isAvailable: Boolean = true
    override val isPlaceholder: Boolean = true
    override fun feed(query: FeedQuery): Flow<List<PostDto>> = flowOf(emptyList())
}
