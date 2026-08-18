package com.myleafy.android.core.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters

/**
 * MyLeafy 本地数据库。阶段 1 只注册课表实体；成绩/考试/随记/日程等在
 * 对应功能迁移阶段加入（见 docs/engineering/android-migration.md 数据模型映射表）。
 */
@Database(
    entities = [CourseEntity::class],
    version = 1,
    exportSchema = false,
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun courseDao(): CourseDao
}
