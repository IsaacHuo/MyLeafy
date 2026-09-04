package com.myleafy.android.features.campus

import android.content.Context
import android.net.Uri
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.data.local.FitnessTestRecordEntity
import com.myleafy.android.core.data.local.MedicalDao
import com.myleafy.android.core.data.local.MedicalLedgerEntryEntity
import com.myleafy.android.core.data.local.MedicalLedgerPhotoEntity
import com.myleafy.android.core.data.local.SportsDao
import com.myleafy.android.core.data.local.SunshineRunRecordEntity
import com.myleafy.android.core.data.local.SunshineRunSettingsEntity
import java.time.LocalDate
import java.util.UUID
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

@OptIn(ExperimentalCoroutinesApi::class)
class CampusLifeRepository(
    private val context: Context,
    private val sportsDao: SportsDao,
    private val medicalDao: MedicalDao,
    private val scopeStore: ActiveAppScopeStore,
) {
    val sunshineRuns: Flow<List<SunshineRunRecordEntity>> = scopeStore.scope.flatMapLatest {
        sportsDao.sunshineRuns(it.scopeKey)
    }
    val sunshineSettings: Flow<SunshineRunSettingsEntity> = scopeStore.scope.flatMapLatest { scope ->
        sportsDao.sunshineSettings(scope.scopeKey).map {
            it ?: SunshineRunSettingsEntity(scopeKey = scope.scopeKey)
        }
    }
    val fitnessTests: Flow<List<FitnessTestRecordEntity>> = scopeStore.scope.flatMapLatest {
        sportsDao.fitnessTests(it.scopeKey)
    }
    val medicalEntries: Flow<List<MedicalLedgerEntryEntity>> = scopeStore.scope.flatMapLatest {
        medicalDao.entries(it.scopeKey)
    }
    val medicalPhotos: Flow<List<MedicalLedgerPhotoEntity>> = scopeStore.scope.flatMapLatest {
        medicalDao.allPhotos(it.scopeKey)
    }

    suspend fun saveRun(date: LocalDate, periodStartWeek: Int, periodEndWeek: Int) {
        val now = System.currentTimeMillis()
        val scopeKey = scopeStore.current.scopeKey
        sportsDao.upsert(
            SunshineRunRecordEntity(
                id = "$scopeKey:${date.toEpochDay()}",
                scopeKey = scopeKey,
                dateEpochDay = date.toEpochDay(),
                periodStartWeek = periodStartWeek,
                periodEndWeek = periodEndWeek,
                createdAt = now,
                updatedAt = now,
            ),
        )
    }

    suspend fun deleteRun(record: SunshineRunRecordEntity) = sportsDao.delete(record)

    suspend fun saveSunshineSettings(total: Int, weeksPerPeriod: Int, periodTarget: Int, excludedWeeks: String) {
        sportsDao.upsert(
            SunshineRunSettingsEntity(
                scopeKey = scopeStore.current.scopeKey,
                totalTarget = total.coerceAtLeast(1),
                weeksPerPeriod = weeksPerPeriod.coerceAtLeast(1),
                periodTarget = periodTarget.coerceAtLeast(1),
                excludedWeeks = excludedWeeks.split(',').map(String::trim).filter(String::isNotEmpty).joinToString(","),
            ),
        )
    }

    suspend fun saveFitnessTest(
        id: String? = null,
        date: LocalDate,
        item: String,
        value: Double,
        unit: String,
        note: String,
    ) {
        val now = System.currentTimeMillis()
        sportsDao.upsert(
            FitnessTestRecordEntity(
                id = id ?: UUID.randomUUID().toString(),
                scopeKey = scopeStore.current.scopeKey,
                testedAt = date.toEpochDay(),
                item = item.trim(),
                value = value,
                unit = unit.trim(),
                note = note.trim(),
                createdAt = now,
                updatedAt = now,
            ),
        )
    }

    suspend fun deleteFitnessTest(record: FitnessTestRecordEntity) = sportsDao.delete(record)

    suspend fun saveMedicalEntry(draft: MedicalLedgerDraft): String {
        val now = System.currentTimeMillis()
        val resolvedId = draft.id ?: UUID.randomUUID().toString()
        medicalDao.upsert(
            MedicalLedgerEntryEntity(
                id = resolvedId,
                scopeKey = scopeStore.current.scopeKey,
                visitDate = draft.visitDate.toEpochDay(),
                hospitalName = draft.hospitalName.trim(),
                department = draft.department.trim(),
                diagnosisNote = draft.diagnosis.trim(),
                scenario = draft.scenario,
                totalExpense = draft.totalExpense,
                estimatedReimbursement = draft.estimatedReimbursement,
                actualReimbursement = draft.actualReimbursement,
                status = draft.status,
                reimbursementDeadline = draft.deadline?.toEpochDay(),
                materialChecklist = draft.materials.trim(),
                note = draft.note.trim(),
                createdAt = now,
                updatedAt = now,
            ),
        )
        return resolvedId
    }

    suspend fun deleteMedicalEntry(entry: MedicalLedgerEntryEntity) {
        medicalDao.photosNow(scopeStore.current.scopeKey, entry.id).forEach { photo ->
            File(photo.localFilename).takeIf(File::isFile)?.delete()
        }
        medicalDao.deletePhotos(scopeStore.current.scopeKey, entry.id)
        medicalDao.delete(entry)
    }

    suspend fun importMedicalPhoto(entryId: String, uri: Uri) = withContext(Dispatchers.IO) {
        val directory = File(context.filesDir, "medical-ledger/${scopeStore.current.scopeKey}").apply { mkdirs() }
        val target = File(directory, "${UUID.randomUUID()}.jpg")
        context.contentResolver.openInputStream(uri)?.use { input -> target.outputStream().use(input::copyTo) }
            ?: error("无法读取所选照片")
        val now = System.currentTimeMillis()
        medicalDao.upsert(
            MedicalLedgerPhotoEntity(
                id = UUID.randomUUID().toString(),
                scopeKey = scopeStore.current.scopeKey,
                entryId = entryId,
                originalFilename = uri.lastPathSegment ?: "医疗凭证.jpg",
                localFilename = target.absolutePath,
                importedAt = now,
                updatedAt = now,
            ),
        )
    }

    suspend fun exportMedicalLedger(entries: List<MedicalLedgerEntryEntity>): File = withContext(Dispatchers.IO) {
        val target = File(context.cacheDir, "medical-exports/medical-ledger.csv").apply { parentFile?.mkdirs() }
        val header = "就诊日期,医院,科室,诊断,场景,总费用,预计报销,实际报销,状态,截止日,材料,备注"
        val rows = entries.map { entry ->
            listOf(
                LocalDate.ofEpochDay(entry.visitDate).toString(), entry.hospitalName, entry.department,
                entry.diagnosisNote, entry.scenario, entry.totalExpense.toString(),
                entry.estimatedReimbursement?.toString().orEmpty(), entry.actualReimbursement?.toString().orEmpty(),
                entry.status, entry.reimbursementDeadline?.let(LocalDate::ofEpochDay)?.toString().orEmpty(),
                entry.materialChecklist, entry.note,
            ).joinToString(",", transform = ::csvCell)
        }
        target.writeText((listOf(header) + rows).joinToString("\n"), Charsets.UTF_8)
        target
    }

    private fun csvCell(value: String): String = "\"${value.replace("\"", "\"\"")}\""
}

data class MedicalLedgerDraft(
    val id: String? = null,
    val visitDate: LocalDate = LocalDate.now(),
    val hospitalName: String = "",
    val department: String = "",
    val diagnosis: String = "",
    val scenario: String = "校内门诊",
    val totalExpense: Double = 0.0,
    val estimatedReimbursement: Double? = null,
    val actualReimbursement: Double? = null,
    val status: String = "待整理材料",
    val deadline: LocalDate? = null,
    val materials: String = "",
    val note: String = "",
)
