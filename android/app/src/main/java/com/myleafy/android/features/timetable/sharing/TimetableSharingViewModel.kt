package com.myleafy.android.features.timetable.sharing

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.services.supabase.SharedTimetableSnapshotDto
import com.myleafy.android.services.supabase.TimetableInviteDto
import com.myleafy.android.services.supabase.TimetableShareMemberDto
import com.myleafy.android.services.supabase.TimetableSharingService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class TimetableSharingUiState(
    val loading: Boolean = true,
    val mutating: Boolean = false,
    val mine: SharedTimetableSnapshotDto? = null,
    val viewable: List<SharedTimetableSnapshotDto> = emptyList(),
    val members: List<TimetableShareMemberDto> = emptyList(),
    val invites: List<TimetableInviteDto> = emptyList(),
    val latestCode: String? = null,
    val acceptCode: String = "",
    val message: String? = null,
    val error: String? = null,
)

class TimetableSharingViewModel(private val repository: TimetableSharingRepository) : ViewModel() {
    private val mutableState = MutableStateFlow(TimetableSharingUiState())
    val uiState: StateFlow<TimetableSharingUiState> = mutableState.asStateFlow()

    init { refresh() }

    fun setInitialCode(code: String?) {
        val normalized = TimetableSharingService.normalizeCode(code.orEmpty()).take(12)
        if (normalized.isNotEmpty()) mutableState.value = mutableState.value.copy(acceptCode = normalized)
    }

    fun setAcceptCode(code: String) {
        mutableState.value = mutableState.value.copy(
            acceptCode = TimetableSharingService.normalizeCode(code).take(12),
            error = null,
        )
    }

    fun refresh() = viewModelScope.launch {
        mutableState.value = mutableState.value.copy(loading = true, error = null)
        runCatching { repository.refresh() }.fold(
            onSuccess = { snapshot ->
                mutableState.value = mutableState.value.copy(
                    loading = false,
                    mine = snapshot.mine,
                    viewable = snapshot.viewable,
                    members = snapshot.members,
                    invites = snapshot.invites,
                )
            },
            onFailure = { mutableState.value = mutableState.value.copy(loading = false, error = it.message ?: "共享课表加载失败") },
        )
    }

    fun publish() = mutate("课表已发布") { repository.publish() }

    fun createInvite() = viewModelScope.launch {
        startMutation()
        runCatching { repository.createInvite() }.fold(
            onSuccess = { invite ->
                mutableState.value = mutableState.value.copy(
                    mutating = false,
                    latestCode = invite.code,
                    message = "邀请码已生成，7 天内单次有效",
                )
                refresh()
            },
            onFailure = ::failMutation,
        )
    }

    fun accept() = mutate("已接受共享课表") { repository.accept(mutableState.value.acceptCode) }
    fun revoke(viewerId: String) = mutate("已撤销该成员") { repository.revoke(viewerId) }
    fun stopSharing() = mutate("已停止共享") { repository.stopSharing() }
    fun leave(ownerId: String) = mutate("已离开共享课表") { repository.leave(ownerId) }

    private fun mutate(success: String, block: suspend () -> Any?) = viewModelScope.launch {
        startMutation()
        runCatching { block() }.fold(
            onSuccess = {
                mutableState.value = mutableState.value.copy(mutating = false, message = success)
                refresh()
            },
            onFailure = ::failMutation,
        )
    }

    private fun startMutation() {
        mutableState.value = mutableState.value.copy(mutating = true, message = null, error = null)
    }

    private fun failMutation(error: Throwable) {
        mutableState.value = mutableState.value.copy(mutating = false, error = error.message ?: "操作失败")
    }
}
