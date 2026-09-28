package com.myleafy.android.features.schedule

import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.test.*
import org.junit.*
import org.junit.Assert.*

@OptIn(ExperimentalCoroutinesApi::class)
class ScheduleViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    @Before fun before() = Dispatchers.setMain(dispatcher)
    @After fun after() = Dispatchers.resetMain()

    @Test fun repeatedSaveAndDeleteCannotOverlapAndFailureCanRetry() = runTest(dispatcher) {
        val repository = FakeScheduleRepository()
        val vm = ScheduleViewModel(repository)
        vm.saveMemo(null, "draft", "title", emptyList())
        vm.saveMemo(null, "duplicate", null, emptyList())
        vm.deleteMemo("existing")
        testScheduler.runCurrent()
        assertEquals(1, repository.saves)
        assertEquals(0, repository.deletes)
        vm.consumeMutation()
        assertEquals(ScheduleMutationState.Saving, vm.mutationState.value)
        repository.pending.completeExceptionally(IllegalStateException("disk full"))
        testScheduler.advanceUntilIdle()
        assertTrue(vm.mutationState.value is ScheduleMutationState.Error)
        repository.pending = CompletableDeferred()
        vm.saveMemo(null, "draft", "title", emptyList())
        testScheduler.runCurrent()
        repository.pending.complete("saved")
        testScheduler.advanceUntilIdle()
        assertEquals(2, repository.saves)
        assertEquals(ScheduleMutationState.Success, vm.mutationState.value)
    }

    @Test fun cancellationDoesNotBecomeAnError() = runTest(dispatcher) {
        val repository = FakeScheduleRepository()
        val vm = ScheduleViewModel(repository)
        vm.saveMemo(null, "draft", null, emptyList())
        testScheduler.runCurrent()
        repository.pending.cancel()
        testScheduler.advanceUntilIdle()
        assertFalse(vm.mutationState.value is ScheduleMutationState.Error)
    }
}

private class FakeScheduleRepository : ScheduleRepository {
    var pending = CompletableDeferred<String>()
    var saves = 0
    var deletes = 0
    override fun memos() = flowOf(emptyList<ScheduleMemoEntity>())
    override fun trashedMemos() = memos()
    override fun events() = flowOf(emptyList<ScheduleEventEntity>())
    override fun eventsInRange(startInclusive: Long, endExclusive: Long) = events()
    override suspend fun memo(id: String): ScheduleMemoEntity? = null
    override suspend fun event(id: String): ScheduleEventEntity? = null
    override suspend fun saveMemo(id: String?, body: String, title: String?, tags: List<String>): String {
        saves++
        return pending.await()
    }
    override suspend fun deleteMemo(id: String) { deletes++ }
    override suspend fun restoreMemo(id: String) = Unit
    override suspend fun permanentlyDeleteMemo(id: String) = Unit
    override suspend fun emptyTrash() = Unit
    override suspend fun saveEvent(id: String?, title: String, startsAt: Long, endsAt: Long, location: String?, note: String?) = "event"
    override suspend fun deleteEvent(id: String) { deletes++ }
}
