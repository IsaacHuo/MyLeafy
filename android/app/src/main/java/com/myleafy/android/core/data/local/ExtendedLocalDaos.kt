package com.myleafy.android.core.data.local

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ScheduleNotificationDao {
    @Query("SELECT * FROM schedule_report_settings WHERE scopeKey = :scopeKey")
    fun settings(scopeKey: String): Flow<List<ScheduleReportSettingEntity>>

    @Query("SELECT * FROM schedule_event_reminders WHERE scopeKey = :scopeKey")
    fun reminders(scopeKey: String): Flow<List<ScheduleEventReminderEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(setting: ScheduleReportSettingEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(reminder: ScheduleEventReminderEntity)

    @Query("DELETE FROM schedule_event_reminders WHERE scopeKey = :scopeKey AND eventId = :eventId")
    suspend fun deleteReminder(scopeKey: String, eventId: String)
}

@Dao
interface SportsDao {
    @Query("SELECT * FROM sunshine_run_records WHERE scopeKey = :scopeKey ORDER BY dateEpochDay DESC")
    fun sunshineRuns(scopeKey: String): Flow<List<SunshineRunRecordEntity>>

    @Query("SELECT * FROM sunshine_run_settings WHERE scopeKey = :scopeKey LIMIT 1")
    fun sunshineSettings(scopeKey: String): Flow<SunshineRunSettingsEntity?>

    @Query("SELECT * FROM fitness_test_records WHERE scopeKey = :scopeKey ORDER BY testedAt DESC")
    fun fitnessTests(scopeKey: String): Flow<List<FitnessTestRecordEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: SunshineRunRecordEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(settings: SunshineRunSettingsEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: FitnessTestRecordEntity)

    @Delete
    suspend fun delete(record: SunshineRunRecordEntity)

    @Delete
    suspend fun delete(record: FitnessTestRecordEntity)
}

@Dao
interface MedicalDao {
    @Query("SELECT * FROM medical_ledger_entries WHERE scopeKey = :scopeKey ORDER BY visitDate DESC")
    fun entries(scopeKey: String): Flow<List<MedicalLedgerEntryEntity>>

    @Query("SELECT * FROM medical_ledger_photos WHERE scopeKey = :scopeKey AND entryId = :entryId ORDER BY importedAt")
    fun photos(scopeKey: String, entryId: String): Flow<List<MedicalLedgerPhotoEntity>>

    @Query("SELECT * FROM medical_ledger_photos WHERE scopeKey = :scopeKey ORDER BY importedAt")
    fun allPhotos(scopeKey: String): Flow<List<MedicalLedgerPhotoEntity>>

    @Query("SELECT * FROM medical_ledger_photos WHERE scopeKey = :scopeKey AND entryId = :entryId")
    suspend fun photosNow(scopeKey: String, entryId: String): List<MedicalLedgerPhotoEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entry: MedicalLedgerEntryEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(photo: MedicalLedgerPhotoEntity)

    @Delete
    suspend fun delete(entry: MedicalLedgerEntryEntity)

    @Delete
    suspend fun delete(photo: MedicalLedgerPhotoEntity)

    @Query("DELETE FROM medical_ledger_photos WHERE scopeKey = :scopeKey AND entryId = :entryId")
    suspend fun deletePhotos(scopeKey: String, entryId: String)
}
