package com.myleafy.android.features.timetable

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.features.timetable.domain.SemesterConfig
import java.time.LocalDate
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed interface TimetableUiState {
    data object Loading : TimetableUiState
    data class Loaded(
        val semesterId: String,
        val week: Int,
        val courses: List<CourseEntity>,
    ) : TimetableUiState

    data class Error(val message: String) : TimetableUiState
}

/** 课表同步状态。 */
sealed interface TimetableSyncState {
    data object Idle : TimetableSyncState
    data object Syncing : TimetableSyncState
    data class Success(val count: Int) : TimetableSyncState
    data class Error(val message: String) : TimetableSyncState
}

/**
 * 课表 ViewModel。本地缓存（Room）实时展示；同步按钮触发
 * 教务抓取（OkHttp + jsoup）→ Room 落库。
 */
class TimetableViewModel(
    private val repository: TimetableRepository,
    private val semesterId: String = SemesterConfig.currentSemesterId,
) : ViewModel() {

    private val _syncState = MutableStateFlow<TimetableSyncState>(TimetableSyncState.Idle)
    val syncState: StateFlow<TimetableSyncState> = _syncState.asStateFlow()

    private val mapped: Flow<TimetableUiState> = repository.coursesForSemester(semesterId)
        .map { courses ->
            TimetableUiState.Loaded(
                semesterId = semesterId,
                week = SemesterConfig.currentWeek(LocalDate.now()),
                courses = courses,
            )
        }

    val uiState: StateFlow<TimetableUiState> = mapped
        .catch { emit(TimetableUiState.Error(it.message ?: "课表加载失败")) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = TimetableUiState.Loading,
        )

    fun refresh() {
        if (_syncState.value is TimetableSyncState.Syncing) return
        _syncState.value = TimetableSyncState.Syncing
        viewModelScope.launch {
            val result = runCatching { repository.refresh(semesterId) }
            _syncState.value = result.fold(
                onSuccess = {
                    val count = (uiState.value as? TimetableUiState.Loaded)?.courses?.size ?: 0
                    TimetableSyncState.Success(count)
                },
                onFailure = { TimetableSyncState.Error(it.message ?: "同步失败") },
            )
        }
    }

    fun consumeSyncResult() {
        if (_syncState.value is TimetableSyncState.Success || _syncState.value is TimetableSyncState.Error) {
            _syncState.value = TimetableSyncState.Idle
        }
    }
}
