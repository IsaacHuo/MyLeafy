package com.myleafy.android.features.community

import com.myleafy.android.services.supabase.CommunityService
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.PostDto
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * 社区仓储接口。Supabase 为权威来源（RLS + campus 作用域）。
 */
interface CommunityRepository {
    val isAvailable: Boolean

    /** 占位实现标识：true 时 UI 提示功能未接入，避免误导。 */
    val isPlaceholder: Boolean

    fun feed(query: FeedQuery): Flow<List<PostDto>>
}

/** 线上仓储：匿名 Auth + community-feed 拉取。 */
class LiveCommunityRepository(
    private val service: CommunityService?,
) : CommunityRepository {

    override val isAvailable: Boolean = true
    override val isPlaceholder: Boolean = false

    override fun feed(query: FeedQuery): Flow<List<PostDto>> = flow {
        val resolved = service ?: throw IllegalStateException("Supabase 未配置，请在 secrets.properties 填写 anon key")
        emit(resolved.fetchFeed(query))
    }
}

/** 占位实现（如无 Supabase 配置时兜底）。 */
class PlaceholderCommunityRepository : CommunityRepository {
    override val isAvailable: Boolean = true
    override val isPlaceholder: Boolean = true
    override fun feed(query: FeedQuery): Flow<List<PostDto>> = flow { emit(emptyList()) }
}
