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
import java.time.ZonedDateTime
import com.myleafy.android.features.timetable.domain.TimetableGridProjection

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

    private val _mutationState = MutableStateFlow<ScheduleMutationState>(ScheduleMutationState.Idle)
    val mutationState: StateFlow<ScheduleMutationState> = _mutationState.asStateFlow()

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

    fun saveMemo(id: String?, body: String, title: String?, tags: List<String>) {
        if (body.isBlank() && title.isNullOrBlank()) return
        _mutationState.value = ScheduleMutationState.Saving
        viewModelScope.launch {
            runCatching {
                repository.saveMemo(
                    id = id,
                    body = body.trim(),
                    title = title?.trim(),
                    tags = tags.map(String::trim).filter(String::isNotEmpty),
                )
            }.fold(
                onSuccess = { _mutationState.value = ScheduleMutationState.Success },
                onFailure = { _mutationState.value = ScheduleMutationState.Error(it.message ?: "随记保存失败") },
            )
        }
    }

    fun saveMemo(draft: MemoDraft) = saveMemo(draft.id, draft.body, draft.title, draft.tags)

    fun deleteMemo(id: String) {
        _mutationState.value = ScheduleMutationState.Saving
        viewModelScope.launch {
            runCatching { repository.deleteMemo(id) }.fold(
                onSuccess = { _mutationState.value = ScheduleMutationState.Success },
                onFailure = { _mutationState.value = ScheduleMutationState.Error(it.message ?: "随记删除失败") },
            )
        }
    }

    fun saveEvent(draft: ScheduleEventDraft) {
        if (draft.title.isBlank()) {
            _mutationState.value = ScheduleMutationState.Error("请填写日程标题")
            return
        }
        if (!draft.endsAt.isAfter(draft.startsAt)) {
            _mutationState.value = ScheduleMutationState.Error("结束时间必须晚于开始时间")
            return
        }
        _mutationState.value = ScheduleMutationState.Saving
        viewModelScope.launch {
            val start = ZonedDateTime.of(draft.date, draft.startsAt, TimetableGridProjection.campusZone)
            val end = ZonedDateTime.of(draft.date, draft.endsAt, TimetableGridProjection.campusZone)
            runCatching {
                repository.saveEvent(
                    id = draft.id,
                    title = draft.title.trim(),
                    startsAt = start.toInstant().toEpochMilli(),
                    endsAt = end.toInstant().toEpochMilli(),
                    location = draft.location.trim(),
                    note = draft.note.trim(),
                )
            }.fold(
                onSuccess = { _mutationState.value = ScheduleMutationState.Success },
                onFailure = { _mutationState.value = ScheduleMutationState.Error(it.message ?: "日程保存失败") },
            )
        }
    }

    fun deleteEvent(id: String) {
        _mutationState.value = ScheduleMutationState.Saving
        viewModelScope.launch {
            runCatching { repository.deleteEvent(id) }.fold(
                onSuccess = { _mutationState.value = ScheduleMutationState.Success },
                onFailure = { _mutationState.value = ScheduleMutationState.Error(it.message ?: "日程删除失败") },
            )
        }
    }

    fun consumeMutation() {
        _mutationState.value = ScheduleMutationState.Idle
    }
}
