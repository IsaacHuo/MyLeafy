package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed interface CampusUiState {
    data object Loading : CampusUiState
    data class Loaded(
        val terms: List<String>,
        val grades: List<GradeEntity>,
        val exams: List<ExamEntity>,
    ) : CampusUiState

    data class Error(val message: String) : CampusUiState
}

sealed interface CampusSyncState {
    data object Idle : CampusSyncState
    data object Syncing : CampusSyncState
    data class Success(val grades: Int, val exams: Int) : CampusSyncState
    data class Error(val message: String) : CampusSyncState
}

/**
 * 校园 ViewModel（成绩/考试入口）。教务为权威来源，Room 为缓存。
 */
class CampusViewModel(
    private val repository: AcademicRepository,
    private val semesterId: String,
) : ViewModel() {

    private val _syncState = MutableStateFlow<CampusSyncState>(CampusSyncState.Idle)
    val syncState: StateFlow<CampusSyncState> = _syncState.asStateFlow()

    private val mapped: Flow<CampusUiState> = combine(
        repository.gradesForTerm(semesterId),
        repository.terms(),
        repository.exams(),
    ) { grades, terms, exams ->
        CampusUiState.Loaded(terms = terms, grades = grades, exams = exams)
    }

    val uiState: StateFlow<CampusUiState> = mapped
        .catch { emit(CampusUiState.Error(it.message ?: "学业数据加载失败")) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = CampusUiState.Loading,
        )

    fun refresh() {
        if (_syncState.value is CampusSyncState.Syncing) return
        _syncState.value = CampusSyncState.Syncing
        viewModelScope.launch {
            val result = runCatching { repository.refresh(semesterId) }
            _syncState.value = result.fold(
                onSuccess = {
                    val state = uiState.value as? CampusUiState.Loaded
                    CampusSyncState.Success(state?.grades?.size ?: 0, state?.exams?.size ?: 0)
                },
                onFailure = { CampusSyncState.Error(it.message ?: "同步失败") },
            )
        }
    }

    fun consumeSyncResult() {
        if (_syncState.value is CampusSyncState.Success || _syncState.value is CampusSyncState.Error) {
            _syncState.value = CampusSyncState.Idle
        }
    }
}
