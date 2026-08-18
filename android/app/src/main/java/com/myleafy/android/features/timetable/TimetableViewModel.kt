package com.myleafy.android.features.timetable

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

data class TimetableUiState(
    val semesterId: String = "",
    val courseCount: Int = 0,
    val isLoading: Boolean = true,
)

/**
 * 课表 ViewModel。阶段 1 展示本地缓存（Room）的课表数量，验证
 * UI → ViewModel → Repository → DataSource 数据链路；教务抓取阶段 2 接入。
 */
class TimetableViewModel(
    repository: TimetableRepository,
    semesterId: String,
) : ViewModel() {

    val uiState: StateFlow<TimetableUiState> = repository.coursesForSemester(semesterId)
        .map { courses ->
            TimetableUiState(
                semesterId = semesterId,
                courseCount = courses.size,
                isLoading = false,
            )
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = TimetableUiState(semesterId = semesterId, isLoading = true),
        )

    private val _refreshing = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = _refreshing.asStateFlow()
}
