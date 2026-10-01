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
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.first

sealed interface ClassroomUiState {
    data object Idle : ClassroomUiState
    data object Loading : ClassroomUiState
    data class Loaded(val rooms: List<EmptyClassroom>, val matrix: com.myleafy.android.parsers.ClassroomAvailability? = null,
        val date: LocalDate? = null, val updatedAt: Long? = null) : ClassroomUiState
    data class Error(val message: String) : ClassroomUiState
}

/**
 * 空闲教室 ViewModel（按需查询，不持久化）。
 */
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class ClassroomViewModel(
    private val repository: ClassroomRepository,
    private val semesterId: String = SemesterConfig.currentSemesterId,
    private val personalDao: com.myleafy.android.core.data.local.CampusPersonalDao? = null,
    private val scopes: com.myleafy.android.core.campus.ActiveAppScopeStore? = null,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ClassroomUiState>(ClassroomUiState.Idle)
    val uiState: StateFlow<ClassroomUiState> = _uiState.asStateFlow()

    /** 当前周（默认本周）。 */
    val currentWeek: Int = SemesterConfig.currentWeek(LocalDate.now())
    val favorites = scopes?.scope?.let { flow ->
        flow.flatMapLatest { scope -> personalDao?.favorites(scope.scopeKey) ?: kotlinx.coroutines.flow.flowOf(emptyList()) }
    } ?: kotlinx.coroutines.flow.flowOf(emptyList<com.myleafy.android.core.data.local.FavoriteClassroomEntity>())

    init { scopes?.let { viewModelScope.launch { it.scope.collect { clearResults() } } } }
    fun toggleFavorite(room: EmptyClassroom) { viewModelScope.launch {
        try {
            val scope = scopes?.current?.scopeKey ?: return@launch
            val dao = personalDao ?: return@launch
            val old = dao.favorites(scope).first().firstOrNull { it.building == room.building && it.room == room.room }
            if (scopes.current.scopeKey != scope) throw kotlinx.coroutines.CancellationException("Identity changed")
            if (old == null) dao.save(com.myleafy.android.core.data.local.FavoriteClassroomEntity(scope, room.building, room.room, System.currentTimeMillis())) else dao.delete(old)
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (failure: Exception) { _uiState.value = ClassroomUiState.Error(failure.message ?: "收藏失败") }
    } }

    fun queryDate(date: LocalDate, start: Int, end: Int) {
        val request = ++generation
        val scope = scopes?.current?.scopeKey
        queryJob?.cancel(); _uiState.value = ClassroomUiState.Loading
        queryJob = viewModelScope.launch {
            try {
                val config = SemesterConfig.timelineConfigurations.firstOrNull { date >= it.semesterStartDate && date < it.semesterStartDate.plusWeeks(it.supportedWeeks.toLong()) }
                    ?: error("所选日期不在已配置学期内")
                val week = (java.time.temporal.ChronoUnit.DAYS.between(config.semesterStartDate, date) / 7 + 1).toInt()
                val matrix = repository.availability(config.semesterId, week, date.dayOfWeek.value)
                val rooms = if (start == 0) emptyList() else matrix.available(start, end)
                if (request == generation && scope == scopes?.current?.scopeKey) _uiState.value = ClassroomUiState.Loaded(rooms, matrix, date, System.currentTimeMillis())
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (failure: Exception) { if (request == generation) _uiState.value = ClassroomUiState.Error(failure.message ?: "查询失败") }
        }
    }

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
