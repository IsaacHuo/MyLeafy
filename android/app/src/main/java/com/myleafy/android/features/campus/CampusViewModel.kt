package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.data.local.GradeRankingEntity
import com.myleafy.android.core.data.local.GradeSummaryEntity
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
        val rankings: List<GradeRankingEntity>,
        val gradeSummary: GradeSummaryEntity?,
        val exams: List<ExamEntity>,
    ) : CampusUiState

    data class Error(val message: String) : CampusUiState
}

sealed interface CampusSyncState {
    data object Idle : CampusSyncState
    data object Syncing : CampusSyncState
    data class Success(
        val grades: Int?,
        val rankings: Int?,
        val exams: Int?,
        val warnings: List<String>,
    ) : CampusSyncState
    data class Error(val message: String) : CampusSyncState
}

enum class AcademicSyncScope { ALL, GRADES_AND_RANKINGS, EXAMS }

/**
 * 校园 ViewModel（成绩/考试入口）。教务为权威来源，Room 为缓存。
 */
class CampusViewModel(
    private val repository: AcademicRepository,
    private val semesterId: String,
) : ViewModel() {

    private val _syncState = MutableStateFlow<CampusSyncState>(CampusSyncState.Idle)
    val syncState: StateFlow<CampusSyncState> = _syncState.asStateFlow()

    private val gradesAndMetadata = combine(
        repository.grades(),
        repository.terms(),
        repository.rankings(),
    ) { grades, terms, rankings -> Triple(grades, terms, rankings) }

    private val academics = combine(
        gradesAndMetadata,
        repository.gradeSummary(),
    ) { (grades, terms, rankings), summary ->
        AcademicSnapshot(grades, terms, rankings, summary)
    }

    private val mapped: Flow<CampusUiState> = combine(
        academics,
        repository.exams(),
    ) { academic, exams ->
        CampusUiState.Loaded(
            terms = academic.terms,
            grades = academic.grades,
            rankings = academic.rankings,
            gradeSummary = academic.summary,
            exams = exams,
        )
    }

    val uiState: StateFlow<CampusUiState> = mapped
        .catch { emit(CampusUiState.Error(it.message ?: "学业数据加载失败")) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = CampusUiState.Loading,
        )

    fun refresh(scope: AcademicSyncScope = AcademicSyncScope.ALL) {
        if (_syncState.value is CampusSyncState.Syncing) return
        _syncState.value = CampusSyncState.Syncing
        viewModelScope.launch {
            val result = runCatching {
                when (scope) {
                    AcademicSyncScope.ALL -> repository.refresh(semesterId)
                    AcademicSyncScope.GRADES_AND_RANKINGS -> repository.refreshGradesAndRankings()
                    AcademicSyncScope.EXAMS -> repository.refreshExams(semesterId)
                }
            }
            _syncState.value = result.fold(
                onSuccess = { refresh ->
                    if (!refresh.hasAnySuccess && refresh.failures.isNotEmpty()) {
                        CampusSyncState.Error(refresh.failures.joinToString("；"))
                    } else {
                        CampusSyncState.Success(
                            grades = refresh.grades,
                            rankings = refresh.rankings,
                            exams = refresh.exams,
                            warnings = refresh.failures,
                        )
                    }
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

    private data class AcademicSnapshot(
        val grades: List<GradeEntity>,
        val terms: List<String>,
        val rankings: List<GradeRankingEntity>,
        val summary: GradeSummaryEntity?,
    )
}
