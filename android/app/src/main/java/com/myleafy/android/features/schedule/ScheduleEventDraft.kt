package com.myleafy.android.features.schedule

import java.time.LocalDate
import java.time.LocalTime

data class ScheduleEventDraft(
    val id: String? = null,
    val title: String,
    val date: LocalDate,
    val startsAt: LocalTime,
    val endsAt: LocalTime,
    val location: String,
    val note: String,
)

sealed interface ScheduleMutationState {
    data object Idle : ScheduleMutationState
    data object Saving : ScheduleMutationState
    data object Success : ScheduleMutationState
    data class Error(val message: String) : ScheduleMutationState
}
