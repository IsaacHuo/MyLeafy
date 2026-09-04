package com.myleafy.android.core.data.local

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

val MIGRATION_4_5 = object : Migration(4, 5) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("CREATE TABLE IF NOT EXISTS `schedule_report_settings` (`scopeKey` TEXT NOT NULL, `mode` TEXT NOT NULL, `enabled` INTEGER NOT NULL, `hour` INTEGER NOT NULL, `minute` INTEGER NOT NULL, PRIMARY KEY(`scopeKey`, `mode`))")
        db.execSQL("CREATE TABLE IF NOT EXISTS `schedule_event_reminders` (`id` TEXT NOT NULL, `scopeKey` TEXT NOT NULL, `eventId` TEXT NOT NULL, `leadMinutes` INTEGER NOT NULL, `enabled` INTEGER NOT NULL, `createdAt` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_schedule_event_reminders_scopeKey` ON `schedule_event_reminders` (`scopeKey`)")
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_schedule_event_reminders_scopeKey_eventId` ON `schedule_event_reminders` (`scopeKey`, `eventId`)")
        db.execSQL("CREATE TABLE IF NOT EXISTS `sunshine_run_records` (`id` TEXT NOT NULL, `scopeKey` TEXT NOT NULL, `dateEpochDay` INTEGER NOT NULL, `periodStartWeek` INTEGER NOT NULL, `periodEndWeek` INTEGER NOT NULL, `createdAt` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_sunshine_run_records_scopeKey` ON `sunshine_run_records` (`scopeKey`)")
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_sunshine_run_records_scopeKey_dateEpochDay` ON `sunshine_run_records` (`scopeKey`, `dateEpochDay`)")
        db.execSQL("CREATE TABLE IF NOT EXISTS `sunshine_run_settings` (`scopeKey` TEXT NOT NULL, `totalTarget` INTEGER NOT NULL, `weeksPerPeriod` INTEGER NOT NULL, `periodTarget` INTEGER NOT NULL, `skipsExcludedWeeks` INTEGER NOT NULL, `excludedWeeks` TEXT NOT NULL, PRIMARY KEY(`scopeKey`))")
        db.execSQL("CREATE TABLE IF NOT EXISTS `fitness_test_records` (`id` TEXT NOT NULL, `scopeKey` TEXT NOT NULL, `testedAt` INTEGER NOT NULL, `item` TEXT NOT NULL, `value` REAL NOT NULL, `unit` TEXT NOT NULL, `note` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_fitness_test_records_scopeKey` ON `fitness_test_records` (`scopeKey`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_fitness_test_records_scopeKey_testedAt` ON `fitness_test_records` (`scopeKey`, `testedAt`)")
        db.execSQL("CREATE TABLE IF NOT EXISTS `medical_ledger_entries` (`id` TEXT NOT NULL, `scopeKey` TEXT NOT NULL, `visitDate` INTEGER NOT NULL, `hospitalName` TEXT NOT NULL, `department` TEXT NOT NULL, `diagnosisNote` TEXT NOT NULL, `scenario` TEXT NOT NULL, `totalExpense` REAL NOT NULL, `estimatedReimbursement` REAL, `actualReimbursement` REAL, `status` TEXT NOT NULL, `reimbursementDeadline` INTEGER, `materialChecklist` TEXT NOT NULL, `note` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_medical_ledger_entries_scopeKey` ON `medical_ledger_entries` (`scopeKey`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_medical_ledger_entries_scopeKey_visitDate` ON `medical_ledger_entries` (`scopeKey`, `visitDate`)")
        db.execSQL("CREATE TABLE IF NOT EXISTS `medical_ledger_photos` (`id` TEXT NOT NULL, `scopeKey` TEXT NOT NULL, `entryId` TEXT NOT NULL, `originalFilename` TEXT NOT NULL, `localFilename` TEXT NOT NULL, `importedAt` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_medical_ledger_photos_scopeKey` ON `medical_ledger_photos` (`scopeKey`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_medical_ledger_photos_scopeKey_entryId` ON `medical_ledger_photos` (`scopeKey`, `entryId`)")
    }
}
