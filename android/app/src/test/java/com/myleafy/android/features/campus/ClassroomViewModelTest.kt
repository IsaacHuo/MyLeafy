package com.myleafy.android.features.campus

import com.myleafy.android.parsers.EmptyClassroom
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ClassroomViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    @Before fun setup() = Dispatchers.setMain(dispatcher)
    @After fun teardown() = Dispatchers.resetMain()
    @Test fun changedConditionsWithdrawResultsAndIgnoreOlderResponses() = runTest(dispatcher) {
        val old = CompletableDeferred<List<EmptyClassroom>>()
        val latest = CompletableDeferred<List<EmptyClassroom>>()
        val repository = object : ClassroomRepository {
            override suspend fun emptyClassrooms(semesterId: String, week: Int, day: Int, startPeriod: Int, endPeriod: Int) =
                withContext(NonCancellable) { if (day == 1) old.await() else latest.await() }
        }
        val model = ClassroomViewModel(repository)
        model.query(1, 1, 1, 12)
        runCurrent()
        model.clearResults()
        assertEquals(ClassroomUiState.Idle, model.uiState.value)
        model.query(1, 2, 1, 12)
        runCurrent()
        latest.complete(listOf(EmptyClassroom("一教", "201")))
        runCurrent()
        old.complete(listOf(EmptyClassroom("一教", "101")))
        advanceUntilIdle()
        assertEquals("201", (model.uiState.value as ClassroomUiState.Loaded).rooms.single().room)
    }
}
