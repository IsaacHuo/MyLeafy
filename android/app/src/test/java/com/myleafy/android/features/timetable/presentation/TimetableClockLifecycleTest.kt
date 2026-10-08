package com.myleafy.android.features.timetable.presentation

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.flowWithLifecycle
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = android.app.Application::class)
@OptIn(ExperimentalCoroutinesApi::class)
class TimetableClockLifecycleTest {
    @Test fun onlyResumedScreensReadTheClockAndResumeWithoutWaitingForTheNextMinute() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val owner = object : LifecycleOwner {
            val registry = LifecycleRegistry.createUnsafe(this)
            override val lifecycle: Lifecycle get() = registry
        }
        var reads = 0
        val start = Instant.parse("2026-10-08T15:59:59.500Z")
        val clock = object : Clock() {
            override fun getZone(): ZoneId = ZoneId.of("UTC")
            override fun withZone(zone: ZoneId): Clock = this
            override fun instant(): Instant { reads++; return start.plusMillis(testScheduler.currentTime) }
        }
        val dates = mutableListOf<java.time.ZonedDateTime>()
        try {
            owner.registry.currentState = Lifecycle.State.CREATED
            val job = backgroundScope.launch {
                timetableMinuteTicks(clock).flowWithLifecycle(owner.lifecycle, Lifecycle.State.RESUMED).collect { dates += it }
            }
            runCurrent()
            assertEquals(0, reads)
            owner.registry.currentState = Lifecycle.State.RESUMED
            runCurrent()
            assertEquals(1, reads)
            owner.registry.currentState = Lifecycle.State.STARTED
            runCurrent()
            advanceTimeBy(90_000); runCurrent()
            assertEquals(1, reads)
            owner.registry.currentState = Lifecycle.State.RESUMED
            runCurrent()
            assertEquals(2, reads)
            assertEquals(java.time.LocalDate.of(2026, 10, 9), dates.last().toLocalDate())
            owner.registry.currentState = Lifecycle.State.DESTROYED
            runCurrent()
            advanceTimeBy(90_000); runCurrent()
            assertEquals(2, reads)
            job.cancel()
        } finally { Dispatchers.resetMain() }
    }
}
