package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.data.local.FitnessTestRecordEntity
import com.myleafy.android.core.data.local.MedicalLedgerEntryEntity
import com.myleafy.android.core.data.local.MedicalLedgerPhotoEntity
import android.net.Uri
import java.io.File
import com.myleafy.android.core.data.local.SunshineRunRecordEntity
import com.myleafy.android.core.data.local.SunshineRunSettingsEntity
import java.time.LocalDate
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class SportsUiState(
    val runs: List<SunshineRunRecordEntity> = emptyList(),
    val settings: SunshineRunSettingsEntity = SunshineRunSettingsEntity("signed-out"),
    val fitnessTests: List<FitnessTestRecordEntity> = emptyList(),
    val loading: Boolean = false,
    val loadFailed: Boolean = false,
)

class SportsViewModel(private val repository: CampusLifeRepository) : ViewModel() {
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    fun dismissError() { _error.value = null }
    fun reportError(error: String) { _error.value = error }
    private val _saving = MutableStateFlow(false)
    val saving = _saving.asStateFlow()
    private fun mutate(onSaved: () -> Unit = {}, block: suspend () -> Unit) {
        if (_saving.value) return
        _saving.value = true
        viewModelScope.launch {
            try { block(); _error.value = null; onSaved() }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { _error.value = failure.message ?: "保存失败" }
            finally { _saving.value = false }
        }
    }

    private val loadRetry = MutableStateFlow(0)
    fun retryLoad() { loadRetry.value += 1; _error.value = null }
    val uiState: StateFlow<SportsUiState> = com.myleafy.android.core.flow.retryableFlow(loadRetry, combine(
        repository.sunshineRuns,
        repository.sunshineSettings,
        repository.fitnessTests,
        { runs, settings, tests -> SportsUiState(runs, settings, tests) },
    ), onError = { _error.value = it.message ?: "体育记录读取失败"; SportsUiState(loadFailed = true) }).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SportsUiState(loading = true))

    fun addRun(date: LocalDate, startWeek: Int, endWeek: Int) = mutate {
        repository.saveRun(date, startWeek, endWeek)
    }

    fun deleteRun(record: SunshineRunRecordEntity) = mutate { repository.deleteRun(record) }

    fun saveRules(total: Int, weeks: Int, perPeriod: Int, excludedWeeks: String, skipsExcludedWeeks: Boolean = true, onSaved: () -> Unit = {}) = mutate(onSaved) {
        repository.saveSunshineSettings(total, weeks, perPeriod, excludedWeeks, skipsExcludedWeeks)
    }

    fun saveFitness(date: LocalDate, item: String, value: Double, unit: String, note: String, id: String? = null, onSaved: () -> Unit = {}) =
        mutate(onSaved) { repository.saveFitnessTest(id = id, date = date, item = item, value = value, unit = unit, note = note) }

    fun deleteFitness(record: FitnessTestRecordEntity) = mutate {
        repository.deleteFitnessTest(record)
    }
}

data class MedicalUiState(
    val entries: List<MedicalLedgerEntryEntity> = emptyList(),
    val photos: List<MedicalLedgerPhotoEntity> = emptyList(),
    val exportedFile: File? = null,
    val loading: Boolean = false,
    val loadFailed: Boolean = false,
)

class MedicalViewModel(private val repository: CampusLifeRepository) : ViewModel() {
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    fun dismissError() { _error.value = null }
    fun reportError(error: String) { _error.value = error }
    private val _saving = MutableStateFlow(false)
    val saving = _saving.asStateFlow()
    private fun mutate(onSaved: () -> Unit = {}, block: suspend () -> Unit) {
        if (_saving.value) return
        _saving.value = true
        viewModelScope.launch {
            try { block(); _error.value = null; onSaved() }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { _error.value = failure.message ?: "保存失败" }
            finally { _saving.value = false }
        }
    }

    private val exportedFile = kotlinx.coroutines.flow.MutableStateFlow<File?>(null)
    private val loadRetry = MutableStateFlow(0)
    fun retryLoad() { loadRetry.value += 1; _error.value = null }
    val uiState: StateFlow<MedicalUiState> = com.myleafy.android.core.flow.retryableFlow(loadRetry, combine(
        repository.medicalEntries,
        repository.medicalPhotos,
        exportedFile,
        { entries, photos, exported -> MedicalUiState(entries, photos, exported) },
    ), onError = { _error.value = it.message ?: "医疗台账读取失败"; MedicalUiState(loadFailed = true) }).stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        MedicalUiState(loading = true),
    )

    fun save(draft: MedicalLedgerDraft, onSaved: () -> Unit = {}) = mutate(onSaved) { repository.saveMedicalEntry(draft) }
    fun delete(entry: MedicalLedgerEntryEntity) = mutate { repository.deleteMedicalEntry(entry) }
    fun importPhoto(entryId: String, uri: Uri) = mutate { repository.importMedicalPhoto(entryId, uri) }
    fun importPhotos(entryId: String, uris: List<Uri>) = mutate {
        val failures = mutableListOf<String>()
        uris.forEachIndexed { index, uri ->
            try { repository.importMedicalPhoto(entryId, uri) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { failures += "第 ${index + 1} 张照片：${failure.message ?: "导入失败"}" }
        }
        check(failures.isEmpty()) { failures.joinToString("；") }
    }
    fun deletePhoto(photo: MedicalLedgerPhotoEntity) = mutate { repository.deleteMedicalPhoto(photo) }
    fun export() = mutate { exportedFile.value = repository.exportMedicalLedger(uiState.value.entries) }
    fun consumeExport() { exportedFile.value = null }
}
