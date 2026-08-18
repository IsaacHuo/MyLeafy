package com.myleafy.android.features.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed interface ScheduleUiState {
    data object Loading : ScheduleUiState
    data class Loaded(
        val memos: List<ScheduleMemoEntity>,
        val events: List<ScheduleEventEntity>,
    ) : ScheduleUiState

    data object Empty : ScheduleUiState
    data class Error(val message: String) : ScheduleUiState
}

/**
 * 日迹 ViewModel。随记与个人日程为本地权威，Room 持久化。
 */
class ScheduleViewModel(
    private val repository: ScheduleRepository,
) : ViewModel() {

    val uiState: StateFlow<ScheduleUiState> = combine(
        repository.memos(),
        repository.events(),
    ) { memos, events ->
        if (memos.isEmpty() && events.isEmpty()) {
            ScheduleUiState.Empty
        } else {
            ScheduleUiState.Loaded(memos = memos, events = events)
        }
    }
        .catch { emit(ScheduleUiState.Error(it.message ?: "日迹加载失败")) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = ScheduleUiState.Loading,
        )

    fun addMemo(body: String, title: String? = null, tags: List<String> = emptyList()) {
        if (body.isBlank()) return
        viewModelScope.launch {
            repository.addMemo(body = body.trim(), title = title, tags = tags)
        }
    }

    fun deleteMemo(id: String) {
        viewModelScope.launch { repository.deleteMemo(id) }
    }

    fun addEvent(title: String, startsAt: Long, endsAt: Long? = null, location: String? = null, note: String? = null) {
        if (title.isBlank()) return
        viewModelScope.launch {
            repository.addEvent(title = title.trim(), startsAt = startsAt, endsAt = endsAt, location = location, note = note)
        }
    }

    fun deleteEvent(id: String) {
        viewModelScope.launch { repository.deleteEvent(id) }
    }
}
