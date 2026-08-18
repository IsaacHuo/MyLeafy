package com.myleafy.android.features.timetable

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.features.timetable.domain.SemesterConfig
import java.time.LocalDate
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

sealed interface TimetableUiState {
    data object Loading : TimetableUiState
    data class Loaded(
        val semesterId: String,
        val week: Int,
        val courses: List<CourseEntity>,
    ) : TimetableUiState

    data class Error(val message: String) : TimetableUiState
}

/**
 * 课表 ViewModel。阶段 1.5 展示本地缓存课程与当前教学周；
 * 教务抓取（OkHttp + jsoup）阶段 2 接入。
 */
class TimetableViewModel(
    repository: TimetableRepository,
    semesterId: String = SemesterConfig.currentSemesterId,
) : ViewModel() {

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
}
