package com.myleafy.android.core.data.local

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(tableName = "schedule_report_settings", primaryKeys = ["scopeKey", "mode"])
data class ScheduleReportSettingEntity(
    val scopeKey: String,
    val mode: String,
    val enabled: Boolean,
    val hour: Int,
    val minute: Int,
)

@Entity(
    tableName = "schedule_event_reminders",
    indices = [Index("scopeKey"), Index(value = ["scopeKey", "eventId"], unique = true)],
)
data class ScheduleEventReminderEntity(
    @PrimaryKey
    val id: String,
    val scopeKey: String,
    val eventId: String,
    val leadMinutes: Int,
    val enabled: Boolean,
    val createdAt: Long,
    val updatedAt: Long,
)

@Entity(tableName = "sunshine_run_records", indices = [Index("scopeKey"), Index(value = ["scopeKey", "dateEpochDay"], unique = true)])
data class SunshineRunRecordEntity(
    @PrimaryKey
    val id: String,
    val scopeKey: String,
    val dateEpochDay: Long,
    val periodStartWeek: Int,
    val periodEndWeek: Int,
    val createdAt: Long,
    val updatedAt: Long,
)

@Entity(tableName = "sunshine_run_settings", primaryKeys = ["scopeKey"])
data class SunshineRunSettingsEntity(
    val scopeKey: String,
    val totalTarget: Int = 34,
    val weeksPerPeriod: Int = 2,
    val periodTarget: Int = 4,
    val skipsExcludedWeeks: Boolean = true,
    val excludedWeeks: String = "3,4,5,17",
)

@Entity(tableName = "fitness_test_records", indices = [Index("scopeKey"), Index(value = ["scopeKey", "testedAt"])])
data class FitnessTestRecordEntity(
    @PrimaryKey
    val id: String,
    val scopeKey: String,
    val testedAt: Long,
    val item: String,
    val value: Double,
    val unit: String,
    val note: String,
    val createdAt: Long,
    val updatedAt: Long,
)

@Entity(tableName = "medical_ledger_entries", indices = [Index("scopeKey"), Index(value = ["scopeKey", "visitDate"])])
data class MedicalLedgerEntryEntity(
    @PrimaryKey
    val id: String,
    val scopeKey: String,
    val visitDate: Long,
    val hospitalName: String,
    val department: String,
    val diagnosisNote: String,
    val scenario: String,
    val totalExpense: Double,
    val estimatedReimbursement: Double?,
    val actualReimbursement: Double?,
    val status: String,
    val reimbursementDeadline: Long?,
    val materialChecklist: String,
    val note: String,
    val createdAt: Long,
    val updatedAt: Long,
)

@Entity(tableName = "medical_ledger_photos", indices = [Index("scopeKey"), Index(value = ["scopeKey", "entryId"])])
data class MedicalLedgerPhotoEntity(
    @PrimaryKey
    val id: String,
    val scopeKey: String,
    val entryId: String,
    val originalFilename: String,
    val localFilename: String,
    val importedAt: Long,
    val updatedAt: Long,
)
