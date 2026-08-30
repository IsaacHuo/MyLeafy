package com.myleafy.android.features.timetable

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.features.campus.AcademicRepository
import com.myleafy.android.features.schedule.ScheduleEventDraft
import com.myleafy.android.features.schedule.ScheduleMutationState
import com.myleafy.android.features.schedule.ScheduleRepository
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.features.timetable.domain.TimetableGridCourse
import com.myleafy.android.features.timetable.domain.TimetableGridExam
import com.myleafy.android.features.timetable.domain.TimetableGridProjection
import com.myleafy.android.features.timetable.domain.TimetableGridScheduleEvent
import com.myleafy.android.features.timetable.domain.TimetableGridSnapshot
import com.myleafy.android.features.timetable.domain.TimetableWeekRange
import com.myleafy.android.features.timetable.export.CalendarExportCourse
import com.myleafy.android.features.timetable.export.CalendarExportScheduleEvent
import com.myleafy.android.features.timetable.export.TimetableCalendarExporter
import java.io.File
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed interface TimetableUiState {
    data object Loading : TimetableUiState
    data class Loaded(
        val semesterId: String,
        val currentWeek: Int,
        val selectedWeek: Int,
        val weekRange: TimetableWeekRange,
        val courses: List<CourseEntity>,
        val exams: List<ExamEntity>,
        val scheduleEvents: List<ScheduleEventEntity>,
        val grid: TimetableGridSnapshot,
    ) : TimetableUiState {
        val week: Int get() = selectedWeek
    }

    data class Error(val message: String) : TimetableUiState
}

sealed interface TimetableSyncState {
    data object Idle : TimetableSyncState
    data object Syncing : TimetableSyncState
    data class Success(val count: Int) : TimetableSyncState
    data class Error(val message: String) : TimetableSyncState
}

sealed interface TimetableExportState {
    data object Idle : TimetableExportState
    data object Exporting : TimetableExportState
    data class Ready(val file: File) : TimetableExportState
    data class Error(val message: String) : TimetableExportState
}

class TimetableViewModel(
    private val repository: TimetableRepository,
    private val academicRepository: AcademicRepository,
    private val scheduleRepository: ScheduleRepository,
    private val semesterId: String = SemesterConfig.currentSemesterId,
    private val calendarExporter: TimetableCalendarExporter = TimetableCalendarExporter(),
) : ViewModel() {

    private val semesterConfig = SemesterConfig.timelineConfigurations
        .firstOrNull { it.semesterId == semesterId }
        ?: SemesterConfig.current
    private val today: LocalDate
        get() = LocalDate.now(TimetableGridProjection.campusZone)
    private val selectedWeek = MutableStateFlow(weekForDate(today))
    private val _syncState = MutableStateFlow<TimetableSyncState>(TimetableSyncState.Idle)
    val syncState: StateFlow<TimetableSyncState> = _syncState.asStateFlow()
    private val _scheduleMutationState = MutableStateFlow<ScheduleMutationState>(ScheduleMutationState.Idle)
    val scheduleMutationState: StateFlow<ScheduleMutationState> = _scheduleMutationState.asStateFlow()
    private val _exportState = MutableStateFlow<TimetableExportState>(TimetableExportState.Idle)
    val exportState: StateFlow<TimetableExportState> = _exportState.asStateFlow()

    private val mapped: Flow<TimetableUiState> = combine(
        repository.coursesForSemester(semesterId),
        academicRepository.exams(),
        scheduleRepository.events(),
        selectedWeek,
    ) { courses, exams, scheduleEvents, week ->
        val weekRange = TimetableWeekRange(
            week = week,
            startDate = semesterConfig.semesterStartDate.plusWeeks((week - 1).toLong()),
        )
        TimetableUiState.Loaded(
            semesterId = semesterId,
            currentWeek = weekForDate(today),
            selectedWeek = week,
            weekRange = weekRange,
            courses = courses,
            exams = exams,
            scheduleEvents = scheduleEvents,
            grid = TimetableGridProjection.project(
                courses = courses.map { it.toGridCourse() },
                exams = exams.mapNotNull { it.toGridExamOrNull() },
                scheduleEvents = scheduleEvents.map { it.toGridScheduleEvent() },
                weekRange = weekRange,
            ),
        )
    }

    val uiState: StateFlow<TimetableUiState> = mapped
        .catch { emit(TimetableUiState.Error(it.message ?: "课表加载失败")) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = TimetableUiState.Loading,
        )

    fun previousWeek() {
        selectedWeek.value = (selectedWeek.value - 1).coerceAtLeast(1)
    }

    fun nextWeek() {
        selectedWeek.value = (selectedWeek.value + 1).coerceAtMost(semesterConfig.supportedWeeks)
    }

    fun goToCurrentWeek() {
        selectedWeek.value = weekForDate(today)
    }

    fun selectWeek(week: Int) {
        selectedWeek.value = week.coerceIn(1, semesterConfig.supportedWeeks)
    }

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

    fun saveScheduleEvent(draft: ScheduleEventDraft) {
        if (_scheduleMutationState.value is ScheduleMutationState.Saving) return
        val title = draft.title.trim()
        if (title.isEmpty()) {
            _scheduleMutationState.value = ScheduleMutationState.Error("请填写日程标题")
            return
        }
        if (!draft.endsAt.isAfter(draft.startsAt)) {
            _scheduleMutationState.value = ScheduleMutationState.Error("结束时间必须晚于开始时间")
            return
        }
        _scheduleMutationState.value = ScheduleMutationState.Saving
        viewModelScope.launch {
            val start = ZonedDateTime.of(draft.date, draft.startsAt, TimetableGridProjection.campusZone)
            val end = ZonedDateTime.of(draft.date, draft.endsAt, TimetableGridProjection.campusZone)
            runCatching {
                scheduleRepository.saveEvent(
                    id = draft.id,
                    title = title,
                    startsAt = start.toInstant().toEpochMilli(),
                    endsAt = end.toInstant().toEpochMilli(),
                    location = draft.location.trim(),
                    note = draft.note.trim(),
                )
            }.fold(
                onSuccess = { _scheduleMutationState.value = ScheduleMutationState.Success },
                onFailure = {
                    _scheduleMutationState.value = ScheduleMutationState.Error(it.message ?: "日程保存失败")
                },
            )
        }
    }

    fun deleteScheduleEvent(id: String) {
        if (_scheduleMutationState.value is ScheduleMutationState.Saving) return
        _scheduleMutationState.value = ScheduleMutationState.Saving
        viewModelScope.launch {
            runCatching { scheduleRepository.deleteEvent(id) }.fold(
                onSuccess = { _scheduleMutationState.value = ScheduleMutationState.Success },
                onFailure = {
                    _scheduleMutationState.value = ScheduleMutationState.Error(it.message ?: "日程删除失败")
                },
            )
        }
    }

    fun consumeScheduleMutation() {
        _scheduleMutationState.value = ScheduleMutationState.Idle
    }

    fun exportCalendar(outputDirectory: File) {
        if (_exportState.value is TimetableExportState.Exporting) return
        val state = uiState.value as? TimetableUiState.Loaded
        if (state == null) {
            _exportState.value = TimetableExportState.Error("课表数据尚未加载完成")
            return
        }
        _exportState.value = TimetableExportState.Exporting
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    calendarExporter.export(
                        outputDirectory = outputDirectory,
                        semesterId = state.semesterId,
                        semesterStartDate = semesterConfig.semesterStartDate,
                        rangeStart = semesterConfig.semesterStartDate,
                        rangeEndExclusive = semesterConfig.semesterStartDate
                            .plusWeeks(semesterConfig.supportedWeeks.toLong()),
                        courses = state.courses.map { course ->
                            CalendarExportCourse(
                                id = course.id,
                                title = course.courseName,
                                teacher = course.teacher,
                                classInfo = course.classInfo,
                                location = course.location,
                                room = course.room,
                                dayOfWeek = course.dayOfWeek,
                                weeks = course.weeks,
                                periods = course.duration,
                            )
                        },
                        scheduleEvents = state.scheduleEvents.map { event ->
                            CalendarExportScheduleEvent(
                                id = event.id,
                                title = event.title,
                                startsAt = event.startsAt,
                                endsAt = event.endsAt,
                                location = event.location,
                                note = event.note,
                            )
                        },
                    )
                }
            }.fold(
                onSuccess = { _exportState.value = TimetableExportState.Ready(it) },
                onFailure = { _exportState.value = TimetableExportState.Error(it.message ?: "ICS 导出失败") },
            )
        }
    }

    fun consumeExportResult() {
        _exportState.value = TimetableExportState.Idle
    }

    fun consumeSyncResult() {
        if (_syncState.value is TimetableSyncState.Success || _syncState.value is TimetableSyncState.Error) {
            _syncState.value = TimetableSyncState.Idle
        }
    }

    private fun weekForDate(date: LocalDate): Int {
        val days = ChronoUnit.DAYS.between(semesterConfig.semesterStartDate, date)
        return if (days < 0) {
            1
        } else {
            ((days + 7) / 7).toInt().coerceIn(1, semesterConfig.supportedWeeks)
        }
    }

    private fun CourseEntity.toGridCourse() = TimetableGridCourse(
        id = id,
        name = courseName,
        teacher = teacher,
        location = location,
        room = room,
        dayOfWeek = dayOfWeek,
        weeks = weeks,
        periods = duration,
    )

    private fun ExamEntity.toGridExamOrNull(): TimetableGridExam? = try {
        TimetableGridExam(
            id = id.toString(),
            name = name,
            location = location,
            date = LocalDate.parse(date, DateTimeFormatter.ISO_LOCAL_DATE),
            startTime = LocalTime.parse(start, flexibleTimeFormatter),
            endTime = LocalTime.parse(end, flexibleTimeFormatter),
        )
    } catch (_: DateTimeParseException) {
        null
    }

    private fun ScheduleEventEntity.toGridScheduleEvent() = TimetableGridScheduleEvent(
        id = id,
        title = title,
        location = location,
        startsAt = startsAt,
        endsAt = endsAt,
    )

    private companion object {
        val flexibleTimeFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("H:mm")
    }
}
