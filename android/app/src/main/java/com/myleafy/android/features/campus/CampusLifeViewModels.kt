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

data class SportsUiState(
    val runs: List<SunshineRunRecordEntity> = emptyList(),
    val settings: SunshineRunSettingsEntity = SunshineRunSettingsEntity("signed-out"),
    val fitnessTests: List<FitnessTestRecordEntity> = emptyList(),
)

class SportsViewModel(private val repository: CampusLifeRepository) : ViewModel() {
    val uiState: StateFlow<SportsUiState> = combine(
        repository.sunshineRuns,
        repository.sunshineSettings,
        repository.fitnessTests,
        ::SportsUiState,
    ).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SportsUiState())

    fun addRun(date: LocalDate, startWeek: Int, endWeek: Int) = viewModelScope.launch {
        repository.saveRun(date, startWeek, endWeek)
    }

    fun deleteRun(record: SunshineRunRecordEntity) = viewModelScope.launch { repository.deleteRun(record) }

    fun saveRules(total: Int, weeks: Int, perPeriod: Int, excludedWeeks: String) = viewModelScope.launch {
        repository.saveSunshineSettings(total, weeks, perPeriod, excludedWeeks)
    }

    fun saveFitness(date: LocalDate, item: String, value: Double, unit: String, note: String) =
        viewModelScope.launch { repository.saveFitnessTest(date = date, item = item, value = value, unit = unit, note = note) }

    fun deleteFitness(record: FitnessTestRecordEntity) = viewModelScope.launch {
        repository.deleteFitnessTest(record)
    }
}

data class MedicalUiState(
    val entries: List<MedicalLedgerEntryEntity> = emptyList(),
    val photos: List<MedicalLedgerPhotoEntity> = emptyList(),
    val exportedFile: File? = null,
)

class MedicalViewModel(private val repository: CampusLifeRepository) : ViewModel() {
    private val exportedFile = kotlinx.coroutines.flow.MutableStateFlow<File?>(null)
    val uiState: StateFlow<MedicalUiState> = combine(
        repository.medicalEntries,
        repository.medicalPhotos,
        exportedFile,
        ::MedicalUiState,
    ).stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        MedicalUiState(),
    )

    fun save(draft: MedicalLedgerDraft) = viewModelScope.launch { repository.saveMedicalEntry(draft) }
    fun delete(entry: MedicalLedgerEntryEntity) = viewModelScope.launch { repository.deleteMedicalEntry(entry) }
    fun importPhoto(entryId: String, uri: Uri) = viewModelScope.launch { repository.importMedicalPhoto(entryId, uri) }
    fun export() = viewModelScope.launch { exportedFile.value = repository.exportMedicalLedger(uiState.value.entries) }
    fun consumeExport() { exportedFile.value = null }
}
