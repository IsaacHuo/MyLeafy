package com.myleafy.android.features.timetable.presentation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.remember
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.features.timetable.domain.TimetableGridProjection
import java.time.Clock
import java.time.ZonedDateTime
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** Cold flow: every foreground subscription reads the clock again, including after midnight. */
internal fun timetableMinuteTicks(clock: Clock): Flow<ZonedDateTime> = flow {
    while (true) {
        val instant = clock.instant()
        emit(instant.atZone(TimetableGridProjection.campusZone))
        delay(60_000L - Math.floorMod(instant.toEpochMilli(), 60_000L))
    }
}

@Composable
internal fun rememberTimetableNow(): State<ZonedDateTime> {
    val clock = remember { Clock.system(TimetableGridProjection.campusZone) }
    val ticks = remember(clock) { timetableMinuteTicks(clock) }
    return ticks.collectAsStateWithLifecycle(
        initialValue = clock.instant().atZone(TimetableGridProjection.campusZone),
        minActiveState = Lifecycle.State.RESUMED,
    )
}
