package com.myleafy.android.core.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters

/**
 * MyLeafy 本地数据库。
 *
 * 阶段 1.5 完整注册各功能本地模型：
 * - 教务副本（学校为权威）：Course / Grade / Exam
 * - 用户本地数据（本地为权威）：ScheduleMemo / ScheduleEvent
 *
 * 社区数据以 Supabase 为权威，不落 Room（见 docs/engineering/android-migration.md）。
 */
@Database(
    entities = [
        CourseEntity::class,
        GradeEntity::class,
        GradeRankingEntity::class,
        GradeSummaryEntity::class,
        ExamEntity::class,
        ScheduleMemoEntity::class,
        ScheduleEventEntity::class,
    ],
    version = 4,
    exportSchema = false,
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun courseDao(): CourseDao
    abstract fun gradeDao(): GradeDao
    abstract fun gradeRankingDao(): GradeRankingDao
    abstract fun gradeSummaryDao(): GradeSummaryDao
    abstract fun examDao(): ExamDao
    abstract fun scheduleMemoDao(): ScheduleMemoDao
    abstract fun scheduleEventDao(): ScheduleEventDao
}
