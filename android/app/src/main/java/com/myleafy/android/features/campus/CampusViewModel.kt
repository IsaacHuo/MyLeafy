package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.data.local.GradeRankingEntity
import com.myleafy.android.core.data.local.GradeSummaryEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.catch
import com.myleafy.android.core.flow.retryableFlow
import kotlinx.coroutines.launch

sealed interface CampusUiState {
    data object Loading : CampusUiState
    data class Loaded(
        val terms: List<String>,
        val grades: List<GradeEntity>,
        val rankings: List<GradeRankingEntity>,
        val gradeSummary: GradeSummaryEntity?,
        val exams: List<ExamEntity>,
        val analytics: GradeAnalytics = GradeAnalytics.calculate(grades, gradeSummary),
        val warnings: List<String> = emptyList(),
    ) : CampusUiState

    data class Error(val message: String) : CampusUiState
}

sealed interface CampusSyncState {
    data object Idle : CampusSyncState
    data object Syncing : CampusSyncState
    data class Success(
        val grades: Int?,
        val rankings: Int?,
        val exams: Int?,
        val warnings: List<String>,
    ) : CampusSyncState
    data class Error(val message: String) : CampusSyncState
}

enum class AcademicSyncScope { ALL, GRADES_AND_RANKINGS, EXAMS, RANKINGS }

/**
 * 校园 ViewModel（成绩/考试入口）。教务为权威来源，Room 为缓存。
 */
class CampusViewModel(
    private val repository: AcademicRepository,
    private val semesterId: String,
) : ViewModel() {

    private val _syncState = MutableStateFlow<CampusSyncState>(CampusSyncState.Idle)
    val syncState: StateFlow<CampusSyncState> = _syncState.asStateFlow()
    private val localErrors = MutableStateFlow<Map<String, String>>(emptyMap())
    private fun <T> supplemental(source: Flow<T>, label: String, empty: T): Flow<T> = source.map { value ->
        if (label in localErrors.value) localErrors.value = localErrors.value - label
        value
    }.catch { failure ->
        if (failure is kotlinx.coroutines.CancellationException) throw failure
        localErrors.value = localErrors.value + (label to "$label：${failure.message ?: "读取失败"}")
        emit(empty)
    }

    private val gradesAndMetadata = combine(
        repository.grades(),
        repository.terms(),
        supplemental(repository.rankings(), "官方排名", emptyList()),
    ) { grades, terms, rankings -> Triple(grades, terms, rankings) }

    private val academics = combine(
        gradesAndMetadata,
        supplemental(repository.gradeSummary(), "官方汇总", null),
    ) { (grades, terms, rankings), summary ->
        AcademicSnapshot(grades, terms, rankings, summary)
    }

    private val mapped: Flow<CampusUiState> = combine(
        academics,
        supplemental(repository.exams(), "考试缓存", emptyList()),
        localErrors,
    ) { academic, exams, errors ->
        CampusUiState.Loaded(
            terms = academic.terms,
            grades = academic.grades,
            rankings = academic.rankings,
            gradeSummary = academic.summary,
            exams = exams,
            warnings = errors.values.toList(),
        )
    }

    /**
     * 本地数据流读取失败后用它重新订阅。
     * [CampusSyncState.Error] 是教务同步失败，走 [refresh]；
     * [CampusUiState.Error] 是本机 Room 读取失败，重试只重新订阅本地数据。
     */
    private val loadRetryToken = MutableStateFlow(0)

    val uiState: StateFlow<CampusUiState> = retryableFlow(
        retryToken = loadRetryToken,
        source = mapped,
        onError = { CampusUiState.Error(it.message ?: "学业数据加载失败") },
    ).stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = CampusUiState.Loading,
    )
    val examUiState: StateFlow<CampusUiState> = retryableFlow(loadRetryToken,
        repository.exams().map<List<ExamEntity>, CampusUiState> { CampusUiState.Loaded(emptyList(), emptyList(), emptyList(), null, it) },
        onError = { CampusUiState.Error(it.message ?: "考试数据加载失败") })
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), CampusUiState.Loading)

    /** 本地读取失败后的原地重试：重新订阅本地数据流，不发起教务请求。 */
    fun retryLoad() {
        loadRetryToken.value += 1
    }

    fun refresh(scope: AcademicSyncScope = AcademicSyncScope.ALL) {
        if (_syncState.value is CampusSyncState.Syncing) return
        _syncState.value = CampusSyncState.Syncing
        viewModelScope.launch {
            val result = runCatching {
                when (scope) {
                    AcademicSyncScope.ALL -> repository.refresh(semesterId)
                    AcademicSyncScope.GRADES_AND_RANKINGS -> repository.refreshGradesAndRankings()
                    AcademicSyncScope.RANKINGS -> repository.refreshRankings()
                    AcademicSyncScope.EXAMS -> repository.refreshExams(semesterId)
                }
            }
            _syncState.value = result.fold(
                onSuccess = { refresh ->
                    if (!refresh.hasAnySuccess && refresh.failures.isNotEmpty()) {
                        CampusSyncState.Error(refresh.failures.joinToString("；"))
                    } else {
                        CampusSyncState.Success(
                            grades = refresh.grades,
                            rankings = refresh.rankings,
                            exams = refresh.exams,
                            warnings = refresh.failures,
                        )
                    }
                },
                onFailure = { if (it is kotlinx.coroutines.CancellationException) throw it; CampusSyncState.Error(it.message ?: "同步失败") },
            )
        }
    }

    fun consumeSyncResult() {
        if (_syncState.value is CampusSyncState.Success || _syncState.value is CampusSyncState.Error) {
            _syncState.value = CampusSyncState.Idle
        }
    }

    private data class AcademicSnapshot(
        val grades: List<GradeEntity>,
        val terms: List<String>,
        val rankings: List<GradeRankingEntity>,
        val summary: GradeSummaryEntity?,
    )
}
