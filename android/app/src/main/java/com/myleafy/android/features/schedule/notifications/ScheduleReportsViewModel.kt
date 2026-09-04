package com.myleafy.android.features.schedule.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.ScheduleEventReminderEntity
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ScheduleReportsUiState(
    val settings: List<ScheduleReportSetting> = ScheduleReportMode.entries.map {
        ScheduleReportSetting(it, false, it.defaultHour, it.defaultMinute)
    },
    val reminders: List<ScheduleEventReminderEntity> = emptyList(),
)

class ScheduleReportsViewModel(
    private val repository: ScheduleNotificationRepository,
    private val scheduler: ScheduleNotificationScheduler,
) : ViewModel() {
    val uiState: StateFlow<ScheduleReportsUiState> = combine(
        repository.settings,
        repository.reminders,
        ::ScheduleReportsUiState,
    ).stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ScheduleReportsUiState(),
    )

    fun setMode(mode: ScheduleReportMode, enabled: Boolean, hour: Int, minute: Int) {
        viewModelScope.launch {
            repository.setMode(mode, enabled, hour, minute)
            scheduler.requestReconcile()
        }
    }

    fun setEventReminder(eventId: String, enabled: Boolean, leadMinutes: Int) {
        viewModelScope.launch {
            repository.setEventReminder(eventId, enabled, leadMinutes)
            scheduler.requestReconcile()
        }
    }
}
