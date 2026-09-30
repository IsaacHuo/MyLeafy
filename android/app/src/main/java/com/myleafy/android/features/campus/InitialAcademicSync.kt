package com.myleafy.android.features.campus

import com.myleafy.android.core.campus.*
import com.myleafy.android.core.data.local.*
import com.myleafy.android.core.network.SchoolNetworkError
import com.myleafy.android.features.timetable.TimetableRepository
import com.myleafy.android.features.timetable.domain.SemesterConfig
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class InitialSyncState(val running: String? = null, val completed: List<String> = emptyList(),
    val failures: Map<String, String> = emptyMap(), val needsAuthentication: Boolean = false) {
    val visible get() = running != null || failures.isNotEmpty() || completed.isNotEmpty()
    val message get() = if (running != null) "正在同步$running…" else buildList {
        if (completed.isNotEmpty()) add("已同步${completed.joinToString("、")}")
        failures.forEach { (name, error) -> add("$name：$error") }
    }.joinToString("；")
}

/** App-owned queue: navigation never cancels it; changing identity does. */
class InitialAcademicSync(
    private val scopes: ActiveAppScopeStore,
    private val dao: TimetablePersonalDao,
    private val timetable: TimetableRepository,
    private val academic: AcademicRepository,
    private val owner: CoroutineScope,
) {
    private val mutable = MutableStateFlow(InitialSyncState())
    val state = mutable.asStateFlow()
    private val mutex = Mutex()
    private var work: Job? = null
    private var started = false
    fun start() {
        if (started) return
        started = true
        owner.launch {
            scopes.scope.map { it.scopeKey }.distinctUntilChanged().collect {
                work?.cancelAndJoin()
                mutable.value = InitialSyncState()
                if (scopes.current.campusId == CampusID.bjfu && !scopes.current.isGuest) launchSync()
            }
        }
    }
    fun retry() { if (work?.isActive != true) launchSync() }
    fun dismiss() { if (mutable.value.running == null) mutable.value = InitialSyncState() }
    fun resumeAfterAuthentication() { if (mutable.value.needsAuthentication) retry() }
    private fun launchSync() {
        val identity = scopes.current
        if (identity.campusId != CampusID.bjfu || identity.isGuest) return
        work = owner.launch {
            mutex.withLock {
                val semester = SemesterConfig.currentSemesterId
                val labels = linkedMapOf("timetable" to "课表", "grades" to "成绩", "exams" to "考试")
                try {
                    val done = dao.checkpoints(identity.scopeKey, semester).map { it.kind }.toMutableSet()
                    // Preserve existing installations: a non-empty local copy already completed initialization.
                    if ("bootstrap" !in done) {
                    for ((kind, present) in listOf(
                        "timetable" to timetable.coursesForSemester(semester).first().isNotEmpty(),
                        "grades" to academic.grades().first().isNotEmpty(),
                        "exams" to academic.exams().first().any { it.date >= SemesterConfig.current.semesterStartDate.toString() },
                    )) if (present && kind !in done) {
                        ensureIdentity(identity.scopeKey)
                        dao.checkpoint(AcademicSyncCheckpoint(identity.scopeKey, semester, kind, System.currentTimeMillis()))
                        done += kind
                    }
                    dao.checkpoint(AcademicSyncCheckpoint(identity.scopeKey, semester, "bootstrap", System.currentTimeMillis()))
                    }
                    val succeeded = mutableListOf<String>()
                    val failed = linkedMapOf<String, String>()
                    for ((kind, label) in labels) {
                        if (kind in done) continue
                        ensureIdentity(identity.scopeKey)
                        mutable.value = InitialSyncState(label, succeeded.toList(), failed.toMap())
                        try {
                            when (kind) {
                                "timetable" -> timetable.refresh(semester)
                                "grades" -> academic.refreshGradesAndRankings().requireComplete()
                                "exams" -> academic.refreshExams(semester).requireComplete()
                            }
                            ensureIdentity(identity.scopeKey)
                            dao.checkpoint(AcademicSyncCheckpoint(identity.scopeKey, semester, kind, System.currentTimeMillis()))
                            succeeded += label
                        } catch (cancelled: CancellationException) { throw cancelled }
                        catch (error: Exception) {
                            failed[label] = error.message ?: "同步失败，请重试"
                            if (error is SchoolNetworkError.AuthenticationExpired) {
                                mutable.value = InitialSyncState(null, succeeded.toList(), failed.toMap(), true)
                                return@withLock
                            }
                        }
                    }
                    mutable.value = InitialSyncState(null, succeeded.toList(), failed.toMap())
                    if (failed.isEmpty()) { delay(4_000); mutable.value = InitialSyncState() }
                } catch (cancelled: CancellationException) { throw cancelled }
                catch (error: Exception) {
                    mutable.value = InitialSyncState(failures = mapOf("同步" to (error.message ?: "无法读取同步状态")))
                }
            }
        }
    }
    private suspend fun ensureIdentity(key: String) {
        currentCoroutineContext().ensureActive()
        if (scopes.current.scopeKey != key) throw CancellationException("Identity changed")
    }
}

private fun AcademicRefreshResult.requireComplete() {
    if (needsAuthentication) throw SchoolNetworkError.SessionExpired
    check(failures.isEmpty()) { failures.joinToString("；") }
}
