package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.data.local.AcademicDocumentDao
import com.myleafy.android.core.data.local.AcademicDocumentEntity
import com.myleafy.android.core.network.SchoolNetworkClient
import com.myleafy.android.parsers.ParsedTeachingPlanSection
import com.myleafy.android.parsers.ParsedTrainingProgram
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

data class AcademicDocumentRefreshResult(
    val teachingPlanSaved: Boolean,
    val trainingProgramSaved: Boolean,
    val failures: List<String>,
) {
    val hasAnySuccess: Boolean get() = teachingPlanSaved || trainingProgramSaved
}

@OptIn(ExperimentalCoroutinesApi::class)
class AcademicDocumentRepository(
    private val client: SchoolNetworkClient,
    private val dao: AcademicDocumentDao,
    private val scopeStore: ActiveAppScopeStore,
) {
    private val json = Json { ignoreUnknownKeys = true }

    fun teachingPlan(): Flow<List<ParsedTeachingPlanSection>> =
        scopeStore.scope.flatMapLatest { dao.document(it.scopeKey, KIND_TEACHING_PLAN) }
            .map { record -> record?.let { decodeTeachingPlan(it.payload) }.orEmpty() }

    fun trainingProgram(): Flow<ParsedTrainingProgram?> =
        scopeStore.scope.flatMapLatest { dao.document(it.scopeKey, KIND_TRAINING_PROGRAM) }
            .map { record -> record?.let { decodeTrainingProgram(it.payload) } }

    suspend fun refresh(): AcademicDocumentRefreshResult {
        val failures = mutableListOf<String>()
        var planSaved = false
        var programSaved = false
        val scopeKey = scopeStore.current.scopeKey
        runCatching { client.fetchTeachingPlan() }
            .onSuccess { plan ->
                dao.upsert(
                    AcademicDocumentEntity(
                        scopeKey = scopeKey,
                        kind = KIND_TEACHING_PLAN,
                        payload = json.encodeToString(plan),
                        updatedAt = System.currentTimeMillis(),
                    ),
                )
                planSaved = true
            }
            .onFailure { failures += it.message ?: "教学计划获取失败" }
        runCatching { client.fetchTrainingProgram() }
            .onSuccess { program ->
                dao.upsert(
                    AcademicDocumentEntity(
                        scopeKey = scopeKey,
                        kind = KIND_TRAINING_PROGRAM,
                        payload = json.encodeToString(program),
                        updatedAt = System.currentTimeMillis(),
                    ),
                )
                programSaved = true
            }
            .onFailure { failures += it.message ?: "培养方案获取失败" }
        return AcademicDocumentRefreshResult(planSaved, programSaved, failures)
    }

    private fun decodeTeachingPlan(payload: String): List<ParsedTeachingPlanSection> =
        runCatching { json.decodeFromString<List<ParsedTeachingPlanSection>>(payload) }.getOrDefault(emptyList())

    private fun decodeTrainingProgram(payload: String): ParsedTrainingProgram? =
        runCatching { json.decodeFromString<ParsedTrainingProgram>(payload) }.getOrNull()

    private companion object {
        const val KIND_TEACHING_PLAN = "teachingPlan"
        const val KIND_TRAINING_PROGRAM = "trainingProgram"
    }
}

enum class TrainingProgramMode(val label: String) {
    TEACHING_PLAN("教学计划"),
    TRAINING_PROGRAM("培养方案"),
}

sealed interface TrainingProgramRefreshState {
    data object Idle : TrainingProgramRefreshState
    data object Loading : TrainingProgramRefreshState
    data class Success(val message: String) : TrainingProgramRefreshState
    data class Error(val message: String) : TrainingProgramRefreshState
}

data class TrainingProgramUiState(
    val mode: TrainingProgramMode = TrainingProgramMode.TRAINING_PROGRAM,
    val teachingPlan: List<ParsedTeachingPlanSection> = emptyList(),
    val trainingProgram: ParsedTrainingProgram? = null,
    val loading: Boolean = true,
    val refreshState: TrainingProgramRefreshState = TrainingProgramRefreshState.Idle,
)

class TrainingProgramViewModel(
    private val repository: AcademicDocumentRepository,
) : ViewModel() {

    private val mode = MutableStateFlow(TrainingProgramMode.TRAINING_PROGRAM)
    private val refreshState = MutableStateFlow<TrainingProgramRefreshState>(TrainingProgramRefreshState.Idle)

    val uiState: StateFlow<TrainingProgramUiState> = combine(
        repository.teachingPlan(),
        repository.trainingProgram(),
        mode,
        refreshState,
    ) { teachingPlan, trainingProgram, currentMode, currentRefresh ->
        TrainingProgramUiState(
            mode = currentMode,
            teachingPlan = teachingPlan,
            trainingProgram = trainingProgram,
            loading = currentRefresh is TrainingProgramRefreshState.Loading,
            refreshState = currentRefresh,
        )
    }
        .catch { emit(TrainingProgramUiState(refreshState = TrainingProgramRefreshState.Error(it.message ?: "教学与培养加载失败"))) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), TrainingProgramUiState())

    fun setMode(value: TrainingProgramMode) {
        mode.value = value
    }

    fun refresh() {
        if (refreshState.value is TrainingProgramRefreshState.Loading) return
        refreshState.value = TrainingProgramRefreshState.Loading
        viewModelScope.launch {
            val result = runCatching { repository.refresh() }
            refreshState.value = result.fold(
                onSuccess = { value ->
                    val message = buildString {
                        append(
                            when {
                                value.teachingPlanSaved && value.trainingProgramSaved -> "教学计划与培养方案已更新"
                                value.teachingPlanSaved -> "教学计划已更新"
                                value.trainingProgramSaved -> "培养方案已更新"
                                else -> "未获取到教学计划或培养方案"
                            },
                        )
                        if (value.failures.isNotEmpty()) append("；${value.failures.joinToString("；")}")
                    }
                    if (value.hasAnySuccess) {
                        TrainingProgramRefreshState.Success(message)
                    } else {
                        TrainingProgramRefreshState.Error(message)
                    }
                },
                onFailure = { TrainingProgramRefreshState.Error(it.message ?: "刷新失败") },
            )
        }
    }

    fun consumeRefreshState() {
        refreshState.value = TrainingProgramRefreshState.Idle
    }
}
