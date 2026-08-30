package com.myleafy.android.features.campus

import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.data.local.GradeRankingEntity
import com.myleafy.android.core.data.local.GradeSummaryEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CampusViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun selectedSyncScopeDoesNotExpandNetworkRequest() = runTest(dispatcher) {
        val repository = FakeAcademicRepository()
        val viewModel = CampusViewModel(repository, semesterId = "2025-2026-2")

        viewModel.refresh(AcademicSyncScope.GRADES_AND_RANKINGS)
        advanceUntilIdle()
        assertEquals(listOf("grades"), repository.calls)

        viewModel.consumeSyncResult()
        viewModel.refresh(AcademicSyncScope.EXAMS)
        advanceUntilIdle()
        assertEquals(listOf("grades", "exams:2025-2026-2"), repository.calls)
    }
}

private class FakeAcademicRepository : AcademicRepository {
    val calls = mutableListOf<String>()

    override fun grades(): Flow<List<GradeEntity>> = flowOf(emptyList())
    override fun gradesForTerm(term: String): Flow<List<GradeEntity>> = flowOf(emptyList())
    override fun terms(): Flow<List<String>> = flowOf(emptyList())
    override fun rankings(): Flow<List<GradeRankingEntity>> = flowOf(emptyList())
    override fun gradeSummary(): Flow<GradeSummaryEntity?> = flowOf(null)
    override fun exams(): Flow<List<ExamEntity>> = flowOf(emptyList())

    override suspend fun refresh(semesterId: String): AcademicRefreshResult {
        calls += "all:$semesterId"
        return AcademicRefreshResult(0, 0, 0, emptyList())
    }

    override suspend fun refreshGradesAndRankings(): AcademicRefreshResult {
        calls += "grades"
        return AcademicRefreshResult(grades = 0, rankings = 0, exams = null, failures = emptyList())
    }

    override suspend fun refreshExams(semesterId: String): AcademicRefreshResult {
        calls += "exams:$semesterId"
        return AcademicRefreshResult(grades = null, rankings = null, exams = 0, failures = emptyList())
    }
}
