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

    fun current(): Flow<ComprehensiveQualityRecordEntity?> =
        scopeStore.scope.flatMapLatest { dao.current(it.scopeKey) }

    fun decodeComponents(record: ComprehensiveQualityRecordEntity?): List<StoredComprehensiveComponent> {
        if (record == null || record.componentsJson.isBlank()) return emptyList()
        return runCatching {
            json.decodeFromString<List<StoredComprehensiveComponent>>(record.componentsJson)
        }.getOrDefault(emptyList())
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
        dao.upsert(
            ComprehensiveQualityRecordEntity(
                scopeKey = scopeStore.current.scopeKey,
                id = "current",
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

    suspend fun clear() = dao.clear(scopeStore.current.scopeKey)
}

data class ComprehensiveQualityUiState(
    val record: ComprehensiveQualityRecordEntity? = null,
    val components: List<StoredComprehensiveComponent> = emptyList(),
    val loading: Boolean = true,
)

class ComprehensiveQualityViewModel(
    private val repository: ComprehensiveQualityRepository,
) : ViewModel() {

    val uiState: StateFlow<ComprehensiveQualityUiState> = repository.current()
        .catch { emit(null) }
        .map { record ->
            ComprehensiveQualityUiState(
                record = record,
                components = repository.decodeComponents(record),
                loading = false,
            )
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ComprehensiveQualityUiState())

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

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
            }.onFailure { _message.value = it.message ?: "保存失败" }
        }
    }

    fun clear() {
        viewModelScope.launch {
            runCatching { repository.clear() }
                .onFailure { _message.value = it.message ?: "清除失败" }
        }
    }

    fun reportError(message: String) {
        _message.value = message
    }

    fun consumeMessage() {
        _message.value = null
    }
}
