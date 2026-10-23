package com.myleafy.android.features.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * 日迹标签/统计/回顾/回收站共用的本地 ViewModel。
 *
 * 只读取当前身份 scopeKey 下的随记；不发起任何网络请求。
 * 读取失败时保留最近一次成功列表并单独暴露错误，不能伪装成“空列表”。
 */
class ScheduleInsightsViewModel(
    private val repository: ScheduleRepository,
) : ViewModel() {

    private var lastMemos: List<ScheduleMemoEntity> = emptyList()
    private var lastTrashed: List<ScheduleMemoEntity> = emptyList()
    private val _readError = MutableStateFlow<String?>(null)
    val readError: StateFlow<String?> = _readError.asStateFlow()

    val memos: StateFlow<List<ScheduleMemoEntity>> = repository.memos()
        .onEach { lastMemos = it; _readError.value = null }
        .catch { error ->
            if (error is CancellationException) throw error
            _readError.value = "随记读取失败：${error.message ?: "请重试"}"
            emit(lastMemos)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val trashed: StateFlow<List<ScheduleMemoEntity>> = repository.trashedMemos()
        .onEach { lastTrashed = it; _readError.value = null }
        .catch { error ->
            if (error is CancellationException) throw error
            _readError.value = "回收站读取失败：${error.message ?: "请重试"}"
            emit(lastTrashed)
        }
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
            runCatching { block() }.onFailure { error ->
                if (error is CancellationException) throw error
                _message.value = error.message ?: failureMessage
            }
        }
    }
}
