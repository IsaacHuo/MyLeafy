package com.myleafy.android.core.data.local

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "favorite_classrooms", primaryKeys = ["scopeKey", "building", "room"])
data class FavoriteClassroomEntity(val scopeKey: String, val building: String, val room: String, val createdAt: Long)

@Entity(tableName = "comprehensive_evidence", primaryKeys = ["scopeKey", "id"])
data class ComprehensiveEvidenceEntity(val scopeKey: String, val id: String, val college: String, val cohort: String,
    val component: String, val originalFilename: String, val localFilename: String, val contentType: String, val importedAt: Long)

@Entity(tableName = "sunshine_reminders", primaryKeys = ["scopeKey"])
data class SunshineReminderEntity(val scopeKey: String, val enabled: Boolean = false, val weekdays: String = "2,4", val hour: Int = 20, val minute: Int = 0)

@Dao interface CampusPersonalDao {
    @Query("SELECT * FROM favorite_classrooms WHERE scopeKey = :scope ORDER BY createdAt DESC")
    fun favorites(scope: String): Flow<List<FavoriteClassroomEntity>>
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun save(value: FavoriteClassroomEntity)
    @Delete suspend fun delete(value: FavoriteClassroomEntity)
    @Query("SELECT * FROM comprehensive_evidence WHERE scopeKey = :scope AND college = :college AND cohort = :cohort ORDER BY importedAt DESC")
    fun evidence(scope: String, college: String, cohort: String): Flow<List<ComprehensiveEvidenceEntity>>
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun save(value: ComprehensiveEvidenceEntity)
    @Delete suspend fun delete(value: ComprehensiveEvidenceEntity)
    @Query("SELECT * FROM sunshine_reminders WHERE scopeKey = :scope LIMIT 1")
    fun reminder(scope: String): Flow<SunshineReminderEntity?>
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun save(value: SunshineReminderEntity)
}
