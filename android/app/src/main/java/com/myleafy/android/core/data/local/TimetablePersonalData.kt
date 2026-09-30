package com.myleafy.android.core.data.local

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "course_notes", primaryKeys = ["scopeKey", "semesterId", "courseKey", "week"])
data class CourseNoteEntity(val scopeKey: String, val semesterId: String, val courseKey: String,
    val week: Int, val text: String, val orphaned: Boolean = false)

@Entity(tableName = "course_reminders", primaryKeys = ["scopeKey", "semesterId", "courseKey"])
data class CourseReminderEntity(val scopeKey: String, val semesterId: String, val courseKey: String,
    val minutes: Int, val anchorPeriod: Int, val orphaned: Boolean = false)

@Entity(tableName = "academic_sync_checkpoints", primaryKeys = ["scopeKey", "semesterId", "kind"])
data class AcademicSyncCheckpoint(val scopeKey: String, val semesterId: String, val kind: String, val updatedAt: Long)

@Dao
interface TimetablePersonalDao {
    @Query("SELECT * FROM course_notes WHERE scopeKey = :scope AND semesterId = :semester")
    fun notes(scope: String, semester: String): Flow<List<CourseNoteEntity>>
    @Query("SELECT * FROM course_reminders WHERE scopeKey = :scope AND semesterId = :semester")
    fun reminders(scope: String, semester: String): Flow<List<CourseReminderEntity>>
    @Upsert suspend fun save(note: CourseNoteEntity)
    @Upsert suspend fun save(reminder: CourseReminderEntity)
    @Query("DELETE FROM course_notes WHERE scopeKey = :scope AND semesterId = :semester AND courseKey = :key AND week = :week")
    suspend fun deleteNote(scope: String, semester: String, key: String, week: Int)
    @Query("DELETE FROM course_reminders WHERE scopeKey = :scope AND semesterId = :semester AND courseKey = :key")
    suspend fun deleteReminder(scope: String, semester: String, key: String)
    @Query("UPDATE course_notes SET orphaned = courseKey NOT IN (:keys) WHERE scopeKey = :scope AND semesterId = :semester")
    suspend fun reconcileNotes(scope: String, semester: String, keys: List<String>)
    @Query("UPDATE course_reminders SET orphaned = courseKey NOT IN (:keys) WHERE scopeKey = :scope AND semesterId = :semester")
    suspend fun reconcileReminders(scope: String, semester: String, keys: List<String>)
    @Query("SELECT * FROM academic_sync_checkpoints WHERE scopeKey = :scope AND semesterId = :semester")
    suspend fun checkpoints(scope: String, semester: String): List<AcademicSyncCheckpoint>
    @Upsert suspend fun checkpoint(value: AcademicSyncCheckpoint)
}

/** Same normalized fields as iOS stableCourseKey; week membership is intentionally excluded. */
fun CourseEntity.stableCourseKey(): String = listOf(sourceSemesterID,
    courseName.trim().replace(Regex("\\s+"), " ").lowercase(),
    teacher.trim().replace(Regex("\\s+"), " ").lowercase(), dayOfWeek.toString(),
    duration.sorted().joinToString("-"),
    location.ifBlank { room }.trim().replace(Regex("\\s+"), " ").lowercase()).joinToString("|")
