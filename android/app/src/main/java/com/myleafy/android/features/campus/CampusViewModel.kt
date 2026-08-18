package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

sealed interface CampusUiState {
    data object Loading : CampusUiState
    data class Loaded(
        val terms: List<String>,
        val grades: List<GradeEntity>,
        val exams: List<ExamEntity>,
    ) : CampusUiState

    data class Error(val message: String) : CampusUiState
}

/**
 * 校园 ViewModel（成绩/考试入口）。教务为权威来源，Room 为缓存；
 * 阶段 2 接入抓取与解析。
 */
class CampusViewModel(
    repository: AcademicRepository,
    private val semesterId: String,
) : ViewModel() {

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
}
