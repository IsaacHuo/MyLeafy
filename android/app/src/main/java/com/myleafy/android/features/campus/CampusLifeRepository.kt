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
import kotlinx.coroutines.flow.first
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

    suspend fun deleteRun(record: SunshineRunRecordEntity) {
        check(record.scopeKey == scopeStore.current.scopeKey) { "账号已切换" }; sportsDao.delete(record)
    }

    suspend fun saveSunshineSettings(total: Int, weeksPerPeriod: Int, periodTarget: Int, excludedWeeks: String, skipsExcludedWeeks: Boolean = true) {
        sportsDao.upsert(
            SunshineRunSettingsEntity(
                scopeKey = scopeStore.current.scopeKey,
                totalTarget = total.coerceAtLeast(1),
                weeksPerPeriod = weeksPerPeriod.coerceAtLeast(1),
                periodTarget = periodTarget.coerceAtLeast(1),
                skipsExcludedWeeks = skipsExcludedWeeks,
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
        val scopeKey = scopeStore.current.scopeKey
        val old = sportsDao.fitnessTests(scopeKey).first().firstOrNull { it.id == id }
        check(scopeKey == scopeStore.current.scopeKey) { "账号已切换" }
        val now = System.currentTimeMillis()
        sportsDao.upsert(
            FitnessTestRecordEntity(
                id = id ?: UUID.randomUUID().toString(),
                scopeKey = scopeKey,
                testedAt = date.toEpochDay(),
                item = item.trim(),
                value = value,
                unit = unit.trim(),
                note = note.trim(),
                createdAt = old?.createdAt ?: now,
                updatedAt = now,
            ),
        )
    }

    suspend fun deleteFitnessTest(record: FitnessTestRecordEntity) {
        check(record.scopeKey == scopeStore.current.scopeKey) { "账号已切换" }; sportsDao.delete(record)
    }

    suspend fun saveMedicalEntry(draft: MedicalLedgerDraft): String {
        val now = System.currentTimeMillis()
        val scopeKey = scopeStore.current.scopeKey
        val old = medicalDao.entries(scopeKey).first().firstOrNull { it.id == draft.id }
        check(scopeKey == scopeStore.current.scopeKey) { "账号已切换" }
        check(draft.id == null || old != null) { "台账已删除" }
        val resolvedId = draft.id ?: UUID.randomUUID().toString()
        medicalDao.upsert(
            MedicalLedgerEntryEntity(
                id = resolvedId,
                scopeKey = scopeKey,
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
                createdAt = old?.createdAt ?: now,
                updatedAt = now,
            ),
        )
        return resolvedId
    }

    suspend fun deleteMedicalEntry(entry: MedicalLedgerEntryEntity) {
        check(entry.scopeKey == scopeStore.current.scopeKey) { "账号已切换" }
        medicalDao.photosNow(scopeStore.current.scopeKey, entry.id).forEach { photo ->
            File(photo.localFilename).takeIf(File::isFile)?.let { check(it.delete()) { "照片删除失败" } }
        }
        medicalDao.deletePhotos(scopeStore.current.scopeKey, entry.id)
        medicalDao.delete(entry)
    }

    suspend fun importMedicalPhoto(entryId: String, uri: Uri) = withContext(Dispatchers.IO) {
        val scopeKey = scopeStore.current.scopeKey
        check(medicalDao.entries(scopeKey).first().any { it.id == entryId }) { "台账已删除" }
        val directory = File(context.filesDir, "medical-ledger/$scopeKey").apply { mkdirs() }
        val target = File(directory, "${UUID.randomUUID()}.jpg")
        try {
            val image = android.graphics.ImageDecoder.decodeBitmap(android.graphics.ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                decoder.allocator = android.graphics.ImageDecoder.ALLOCATOR_SOFTWARE
                val sample = kotlin.math.ceil(maxOf(info.size.width, info.size.height) / 2400.0).toInt().coerceAtLeast(1)
                decoder.setTargetSampleSize(sample)
            }
            try { target.outputStream().use { check(image.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, it)) { "照片保存失败" } } }
            finally { image.recycle() }
            check(scopeStore.current.scopeKey == scopeKey) { "账号已切换" }
        val now = System.currentTimeMillis()
        medicalDao.upsert(
            MedicalLedgerPhotoEntity(
                id = UUID.randomUUID().toString(),
                scopeKey = scopeKey,
                entryId = entryId,
                originalFilename = uri.lastPathSegment ?: "医疗凭证.jpg",
                localFilename = target.absolutePath,
                importedAt = now,
                updatedAt = now,
            ),
        )
        } catch (failure: Exception) { target.delete(); throw failure }
    }

    suspend fun deleteMedicalPhoto(photo: MedicalLedgerPhotoEntity) = withContext(Dispatchers.IO) {
        check(photo.scopeKey == scopeStore.current.scopeKey) { "账号已切换" }
        val file = File(photo.localFilename)
        check(!file.exists() || file.delete()) { "照片删除失败" }
        medicalDao.delete(photo)
    }

    suspend fun exportMedicalLedger(entries: List<MedicalLedgerEntryEntity>): File = withContext(Dispatchers.IO) {
        val scopeKey = scopeStore.current.scopeKey
        check(entries.all { it.scopeKey == scopeKey }) { "账号已切换" }
        val photos = medicalDao.allPhotos(scopeKey).first().filter { photo -> entries.any { it.id == photo.entryId } }
        photos.forEach { check(File(it.localFilename).isFile) { "凭证照片缺失：${it.originalFilename}" } }
        val target = File(context.cacheDir, "medical-exports/medical-ledger-${UUID.randomUUID()}.zip").apply { parentFile?.mkdirs() }
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
        val policy = MedicalPolicy.load(context)
        val manifest = kotlinx.serialization.json.buildJsonObject {
            put("policyUpdatedAt", kotlinx.serialization.json.JsonPrimitive(policy.policyUpdatedAt))
            put("hospitalInfoUpdatedAt", kotlinx.serialization.json.JsonPrimitive(policy.hospitalInfoUpdatedAt))
            put("entries", kotlinx.serialization.json.JsonArray(entries.map { entry -> kotlinx.serialization.json.buildJsonObject {
                put("id", kotlinx.serialization.json.JsonPrimitive(entry.id))
                put("visitDate", kotlinx.serialization.json.JsonPrimitive(LocalDate.ofEpochDay(entry.visitDate).toString()))
                put("hospitalName", kotlinx.serialization.json.JsonPrimitive(entry.hospitalName))
                put("department", kotlinx.serialization.json.JsonPrimitive(entry.department))
                put("diagnosis", kotlinx.serialization.json.JsonPrimitive(entry.diagnosisNote))
                put("scenario", kotlinx.serialization.json.JsonPrimitive(entry.scenario))
                put("totalExpense", kotlinx.serialization.json.JsonPrimitive(entry.totalExpense))
                put("estimatedReimbursement", entry.estimatedReimbursement?.let { kotlinx.serialization.json.JsonPrimitive(it) } ?: kotlinx.serialization.json.JsonNull)
                put("actualReimbursement", entry.actualReimbursement?.let { kotlinx.serialization.json.JsonPrimitive(it) } ?: kotlinx.serialization.json.JsonNull)
                put("status", kotlinx.serialization.json.JsonPrimitive(entry.status))
                put("deadline", entry.reimbursementDeadline?.let { kotlinx.serialization.json.JsonPrimitive(LocalDate.ofEpochDay(it).toString()) } ?: kotlinx.serialization.json.JsonNull)
                put("materials", kotlinx.serialization.json.JsonArray(entry.materialChecklist.split('|').filter(String::isNotBlank).map { kotlinx.serialization.json.JsonPrimitive(it) }))
                put("note", kotlinx.serialization.json.JsonPrimitive(entry.note))
                put("createdAt", kotlinx.serialization.json.JsonPrimitive(entry.createdAt))
                put("updatedAt", kotlinx.serialization.json.JsonPrimitive(entry.updatedAt))
                put("photos", kotlinx.serialization.json.JsonArray(photos.filter { it.entryId == entry.id }.map { photo -> kotlinx.serialization.json.buildJsonObject {
                    put("originalFilename", kotlinx.serialization.json.JsonPrimitive(photo.originalFilename))
                    put("path", kotlinx.serialization.json.JsonPrimitive("photos/${entry.id}/${File(photo.localFilename).name}"))
                } }))
            } }))
        }
        try {
            java.util.zip.ZipOutputStream(target.outputStream()).use { zip ->
                fun textEntry(name: String, text: String) { zip.putNextEntry(java.util.zip.ZipEntry(name)); zip.write(text.toByteArray(Charsets.UTF_8)); zip.closeEntry() }
                textEntry("medical-ledger.csv", "\uFEFF" + (listOf(header) + rows).joinToString("\n"))
                textEntry("manifest.json", manifest.toString())
                photos.forEach { photo -> zip.putNextEntry(java.util.zip.ZipEntry("photos/${photo.entryId}/${File(photo.localFilename).name}")); File(photo.localFilename).inputStream().use { it.copyTo(zip) }; zip.closeEntry() }
            }
            check(scopeKey == scopeStore.current.scopeKey) { "账号已切换" }
        } catch (failure: Exception) { target.delete(); throw failure }
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
    val scenario: String = "校医院门急诊",
    val totalExpense: Double = 0.0,
    val estimatedReimbursement: Double? = null,
    val actualReimbursement: Double? = null,
    val status: String = "待整理",
    val deadline: LocalDate? = null,
    val materials: String = "",
    val note: String = "",
)
