package com.myleafy.android.features.campus

import com.myleafy.android.core.campus.*
import com.myleafy.android.core.data.local.*
import com.myleafy.android.core.network.*
import com.myleafy.android.features.timetable.TimetableRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class InitialAcademicSyncTest {
    private class Fixtures {
        val scopes = ActiveAppScopeStore()
        val dao = MemoryDao()
        val calls = mutableListOf<String>()
        var gradeError: String? = null
        var expired = false
        var waitForTimetable: CompletableDeferred<Unit>? = null
        val timetable = object : TimetableRepository {
            override fun coursesForSemester(semesterId: String) = flowOf(emptyList<CourseEntity>())
            override suspend fun refresh(semesterId: String, onStage: (AcademicStage) -> Unit): TimetableRefreshResult {
                calls += "timetable"
                waitForTimetable?.await()
                return TimetableRefreshResult(0, 0, false)
            }
        }
        val academic = object : AcademicRepository {
            override fun grades() = flowOf(emptyList<GradeEntity>())
            override fun gradesForTerm(term: String) = grades()
            override fun terms() = flowOf(emptyList<String>())
            override fun rankings() = flowOf(emptyList<GradeRankingEntity>())
            override fun gradeSummary() = flowOf<GradeSummaryEntity?>(null)
            override fun exams() = flowOf(emptyList<ExamEntity>())
            override suspend fun refresh(semesterId: String) = error("Unexpected expanded request")
            override suspend fun refreshRankings() = error("Unexpected ranking request")
            override suspend fun refreshGradesAndRankings(): AcademicRefreshResult {
                calls += "grades"
                return AcademicRefreshResult(0, 0, null, gradeError?.let(::listOf).orEmpty(), expired)
            }
            override suspend fun refreshExams(semesterId: String): AcademicRefreshResult {
                calls += "exams"
                return AcademicRefreshResult(null, null, 0, emptyList())
            }
        }
        fun login() = scopes.activate(CampusIdentity(CampusID.bjfu, "fixture", null, SchoolPortal.UNDERGRADUATE, CampusIdentity.IdentityKind.SCHOOL_PORTAL))
        fun queue(owner: CoroutineScope) = InitialAcademicSync(scopes, dao, timetable, academic, owner)
    }

    @Test fun trustedEmptySuccessIsCheckpointedAndNotRepeatedOnRestart() = runTest {
        val f = Fixtures(); f.login()
        f.queue(backgroundScope).start(); runCurrent()
        assertEquals(listOf("timetable", "grades", "exams"), f.calls)
        f.queue(backgroundScope).start(); runCurrent()
        assertEquals(3, f.calls.size)
    }

    @Test fun partialFailureRetriesOnlyFailedRangeAndDoesNotExpandIt() = runTest {
        val f = Fixtures(); f.login(); f.gradeError = "断网"
        val q = f.queue(backgroundScope); q.start(); runCurrent()
        assertEquals(listOf("timetable", "grades", "exams"), f.calls)
        assertEquals(setOf("成绩"), q.state.value.failures.keys)
        f.gradeError = null; q.retry(); q.retry(); runCurrent()
        assertEquals(listOf("timetable", "grades", "exams", "grades"), f.calls)
    }

    @Test fun expiredSessionPausesAndReauthenticationResumesRemainingQueue() = runTest {
        val f = Fixtures(); f.login(); f.expired = true
        val q = f.queue(backgroundScope); q.start(); runCurrent()
        assertEquals(listOf("timetable", "grades"), f.calls)
        assertTrue(q.state.value.needsAuthentication)
        f.expired = false; q.resumeAfterAuthentication(); runCurrent()
        assertEquals(listOf("timetable", "grades", "grades", "exams"), f.calls)
    }

    @Test fun guestDoesNotRequestAndIdentitySwitchCancelsInFlightWork() = runTest {
        val f = Fixtures(); f.scopes.activateGuest("local")
        val q = f.queue(backgroundScope); q.start(); runCurrent()
        assertTrue(f.calls.isEmpty())
        f.waitForTimetable = CompletableDeferred(); f.login(); runCurrent()
        f.scopes.activateGuest("other"); runCurrent(); f.waitForTimetable!!.complete(Unit); runCurrent()
        assertEquals(listOf("timetable"), f.calls)
        assertFalse(f.dao.saved.any { it.kind == "timetable" })
        assertFalse(q.state.value.visible)
    }
}

private class MemoryDao : TimetablePersonalDao {
    val saved = mutableListOf<AcademicSyncCheckpoint>()
    override fun notes(scope: String, semester: String) = flowOf(emptyList<CourseNoteEntity>())
    override fun reminders(scope: String, semester: String) = flowOf(emptyList<CourseReminderEntity>())
    override suspend fun save(note: CourseNoteEntity) = Unit
    override suspend fun save(reminder: CourseReminderEntity) = Unit
    override suspend fun deleteNote(scope: String, semester: String, key: String, week: Int) = Unit
    override suspend fun deleteReminder(scope: String, semester: String, key: String) = Unit
    override suspend fun reconcileNotes(scope: String, semester: String, keys: List<String>) = Unit
    override suspend fun reconcileReminders(scope: String, semester: String, keys: List<String>) = Unit
    override suspend fun checkpoints(scope: String, semester: String) = saved.filter { it.scopeKey == scope && it.semesterId == semester }
    override suspend fun checkpoint(value: AcademicSyncCheckpoint) { saved.removeAll { it.scopeKey == value.scopeKey && it.semesterId == value.semesterId && it.kind == value.kind }; saved += value }
}
