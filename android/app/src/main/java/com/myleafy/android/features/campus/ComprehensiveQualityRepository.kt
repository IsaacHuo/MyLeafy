package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.data.local.ComprehensiveQualityDao
import com.myleafy.android.core.data.local.ComprehensiveQualityRecordEntity
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class StoredComprehensiveComponent(
    val kind: String,
    val rawScore: Double? = null,
    val peerMaxScore: Double? = null,
    val officialStandardScore: Double? = null,
    val materialReady: Boolean = false,
    val note: String = "",
)

@OptIn(ExperimentalCoroutinesApi::class)
class ComprehensiveQualityRepository(
    private val dao: ComprehensiveQualityDao,
    private val scopeStore: ActiveAppScopeStore,
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val college = MutableStateFlow("园林学院")
    fun selectCollege(value: String) { college.value = value }

    fun current(): Flow<ComprehensiveQualityRecordEntity?> =
        kotlinx.coroutines.flow.combine(scopeStore.scope, college) { scope, selected -> scope.scopeKey to selected }
            .flatMapLatest { (scope, selected) -> dao.current(scope, selected) }

    fun decodeComponents(record: ComprehensiveQualityRecordEntity?): List<StoredComprehensiveComponent> {
        if (record == null || record.componentsJson.isBlank()) return emptyList()
        return json.decodeFromString<List<StoredComprehensiveComponent>>(record.componentsJson)
    }

    suspend fun save(
        collegeName: String,
        cohort: String,
        academicStandardScore: Double?,
        officialQualityScore: Double?,
        officialCompositeScore: Double?,
        note: String,
        components: List<StoredComprehensiveComponent>,
    ) {
        dao.saveForCollege(
            ComprehensiveQualityRecordEntity(
                scopeKey = scopeStore.current.scopeKey,
                id = "$collegeName|$cohort",
                collegeName = collegeName,
                cohort = cohort,
                academicStandardScore = academicStandardScore,
                officialQualityScore = officialQualityScore,
                officialCompositeScore = officialCompositeScore,
                note = note,
                componentsJson = json.encodeToString(components),
                updatedAt = System.currentTimeMillis(),
            ),
        )
    }

    suspend fun clear() = dao.clear(scopeStore.current.scopeKey, college.value)
}

data class ComprehensiveQualityUiState(
    val record: ComprehensiveQualityRecordEntity? = null,
    val components: List<StoredComprehensiveComponent> = emptyList(),
    val loading: Boolean = true,
)

class ComprehensiveQualityViewModel(
    private val repository: ComprehensiveQualityRepository,
) : ViewModel() {
    fun selectCollege(value: String) { repository.selectCollege(value) }

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()
    private val _loadFailed = MutableStateFlow(false)
    val loadFailed: StateFlow<Boolean> = _loadFailed.asStateFlow()
    private val retry = MutableStateFlow(0)
    val uiState: StateFlow<ComprehensiveQualityUiState> = com.myleafy.android.core.flow.retryableFlow(
        retry,
        repository.current().map { record ->
            ComprehensiveQualityUiState(record, repository.decodeComponents(record), loading = false)
        },
        onError = { error ->
            _loadFailed.value = true
            _message.value = error.message ?: "读取失败"
            ComprehensiveQualityUiState(loading = false)
        },
    ).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ComprehensiveQualityUiState())

    fun retryLoad() { _loadFailed.value = false; _message.value = null; retry.value += 1 }

    fun save(
        collegeName: String,
        cohort: String,
        academicStandardScore: Double?,
        officialQualityScore: Double?,
        officialCompositeScore: Double?,
        note: String,
        components: List<StoredComprehensiveComponent>,
    ) {
        viewModelScope.launch {
            runCatching {
                repository.save(
                    collegeName = collegeName,
                    cohort = cohort,
                    academicStandardScore = academicStandardScore,
                    officialQualityScore = officialQualityScore,
                    officialCompositeScore = officialCompositeScore,
                    note = note,
                    components = components,
                )
            }.onSuccess { _message.value = null }
                .onFailure { if (it is kotlinx.coroutines.CancellationException) throw it; _message.value = it.message ?: "保存失败" }
        }
    }

    fun clear() {
        viewModelScope.launch {
            runCatching { repository.clear() }
                .onSuccess { _message.value = null }
                .onFailure { if (it is kotlinx.coroutines.CancellationException) throw it; _message.value = it.message ?: "清除失败" }
        }
    }

    fun reportError(message: String) {
        _message.value = message
    }

    fun consumeMessage() {
        _message.value = null
    }
}
