package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.parsers.EmptyClassroom
import java.time.LocalDate
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface ClassroomUiState {
    data object Idle : ClassroomUiState
    data object Loading : ClassroomUiState
    data class Loaded(val rooms: List<EmptyClassroom>) : ClassroomUiState
    data class Error(val message: String) : ClassroomUiState
}

/**
 * 空闲教室 ViewModel（按需查询，不持久化）。
 */
class ClassroomViewModel(
    private val repository: ClassroomRepository,
    private val semesterId: String = SemesterConfig.currentSemesterId,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ClassroomUiState>(ClassroomUiState.Idle)
    val uiState: StateFlow<ClassroomUiState> = _uiState.asStateFlow()

    /** 当前周（默认本周）。 */
    val currentWeek: Int = SemesterConfig.currentWeek(LocalDate.now())

    private var queryJob: kotlinx.coroutines.Job? = null
    private var generation = 0

    fun clearResults() {
        generation += 1
        queryJob?.cancel()
        _uiState.value = ClassroomUiState.Idle
    }

    fun query(week: Int, day: Int, startPeriod: Int, endPeriod: Int) {
        val request = ++generation
        queryJob?.cancel()
        _uiState.value = ClassroomUiState.Loading
        queryJob = viewModelScope.launch {
            try {
                val rooms = repository.emptyClassrooms(semesterId, week, day, startPeriod, endPeriod)
                if (request == generation) _uiState.value = ClassroomUiState.Loaded(rooms)
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (failure: Exception) {
                if (request == generation) _uiState.value = ClassroomUiState.Error(failure.message ?: "查询失败")
            }
        }
    }
}
