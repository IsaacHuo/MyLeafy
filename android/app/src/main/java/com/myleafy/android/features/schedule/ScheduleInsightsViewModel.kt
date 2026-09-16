package com.myleafy.android.features.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * 日迹标签/统计/回顾/回收站共用的本地 ViewModel。
 *
 * 只读取当前身份 scopeKey 下的随记；不发起任何网络请求。
 */
class ScheduleInsightsViewModel(
    private val repository: ScheduleRepository,
) : ViewModel() {

    val memos: StateFlow<List<ScheduleMemoEntity>> = repository.memos()
        .catch { emit(emptyList()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val trashed: StateFlow<List<ScheduleMemoEntity>> = repository.trashedMemos()
        .catch { emit(emptyList()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    fun restore(id: String) = run("恢复失败") { repository.restoreMemo(id) }

    fun deleteForever(id: String) = run("删除失败") { repository.permanentlyDeleteMemo(id) }

    fun emptyTrash() = run("清空回收站失败") { repository.emptyTrash() }

    fun consumeMessage() {
        _message.value = null
    }

    private fun run(failureMessage: String, block: suspend () -> Unit) {
        viewModelScope.launch {
            runCatching { block() }.onFailure { _message.value = it.message ?: failureMessage }
        }
    }
}
