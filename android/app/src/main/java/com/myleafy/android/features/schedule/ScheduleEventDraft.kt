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

internal val scheduleDraftSaver = androidx.compose.runtime.saveable.Saver<ScheduleEventDraft?, List<String>>(
    save = { draft ->
        draft?.let {
            listOf(
                it.id.orEmpty(),
                it.title,
                it.date.toString(),
                it.startsAt.toString(),
                it.endsAt.toString(),
                it.location,
                it.note,
            )
        }
    },
    restore = { values ->
        ScheduleEventDraft(
            id = values[0].ifBlank { null },
            title = values[1],
            date = LocalDate.parse(values[2]),
            startsAt = LocalTime.parse(values[3]),
            endsAt = LocalTime.parse(values[4]),
            location = values[5],
            note = values[6],
        )
    },
)
