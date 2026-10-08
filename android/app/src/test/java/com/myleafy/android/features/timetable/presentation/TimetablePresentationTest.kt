package com.myleafy.android.features.timetable.presentation

import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TimetablePresentationTest {
    @Test fun cumulativeRowsEndAtTheViewportInsteadOfAccumulatingRoundingError() {
        for (height in listOf(480, 637, 911, 1440)) {
            val geometry = TimetableGridGeometry(height, 101, 112f)
            assertEquals(height, geometry.rowEdge(13))
            assertTrue((1..13).all { geometry.rowHeight(it) > 0 })
            assertTrue((1..13).map { geometry.rowHeight(it) }.let { it.max() - it.min() <= 1 })
        }
    }

    @Test fun tallViewportCapsBothAxisAndGridAtTheSameBoundary() {
        val geometry = TimetableGridGeometry(2000, 101, 112f)
        assertEquals(101 + 112 * 13, geometry.rowEdge(13))
        assertEquals(geometry.rowEdge(6), geometry.timelineY(6f))
    }

    @Test fun fractionalDensityRoundsTheWholeGridRatherThanEachRow() {
        val geometry = TimetableGridGeometry(2000, 101, 112.4f)
        assertEquals(101 + 1461, geometry.rowEdge(13))
    }

    @Test fun minuteTicksUseCampusDateAndCrossMidnightWithoutInteraction() = runTest {
        val start = Instant.parse("2026-10-08T15:59:59.500Z")
        val clock = object : Clock() {
            override fun getZone(): ZoneId = ZoneId.of("UTC")
            override fun withZone(zone: ZoneId): Clock = this
            override fun instant(): Instant = start.plusMillis(testScheduler.currentTime)
        }
        val values = mutableListOf<java.time.ZonedDateTime>()
        val job = launch { timetableMinuteTicks(clock).take(3).toList(values) }
        runCurrent()
        assertEquals(LocalDate.of(2026, 10, 8), values.single().toLocalDate())
        advanceTimeBy(500); runCurrent()
        assertEquals(LocalDate.of(2026, 10, 9), values.last().toLocalDate())
        assertEquals(0, values.last().second)
        advanceTimeBy(60_000); runCurrent()
        assertEquals(1, values.last().minute)
        job.join()
    }

    @Test fun foregroundResubscriptionImmediatelyReadsTheNewTime() = runTest {
        var instant = Instant.parse("2026-10-08T01:00:00Z")
        val clock = object : Clock() {
            override fun getZone(): ZoneId = ZoneId.of("UTC")
            override fun withZone(zone: ZoneId): Clock = this
            override fun instant(): Instant = instant
        }
        val ticks = timetableMinuteTicks(clock)
        assertEquals(9, ticks.take(1).toList().single().hour)
        instant = instant.plusSeconds(3600)
        assertEquals(10, ticks.take(1).toList().single().hour)
    }
}
