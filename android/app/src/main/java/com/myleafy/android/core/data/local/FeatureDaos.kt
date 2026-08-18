package com.myleafy.android.core.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface GradeDao {
    @Query("SELECT * FROM grades WHERE term = :term ORDER BY courseName")
    fun gradesForTerm(term: String): Flow<List<GradeEntity>>

    @Query("SELECT DISTINCT term FROM grades ORDER BY term DESC")
    fun availableTerms(): Flow<List<String>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(grades: List<GradeEntity>)

    @Query("DELETE FROM grades")
    suspend fun clearAll()
}

@Dao
interface ExamDao {
    @Query("SELECT * FROM exams ORDER BY date, start")
    fun all(): Flow<List<ExamEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(exams: List<ExamEntity>)

    @Query("DELETE FROM exams")
    suspend fun clearAll()
}

@Dao
interface ScheduleMemoDao {
    @Query("SELECT * FROM schedule_memos WHERE trashedAt IS NULL ORDER BY pinnedAt DESC, updatedAt DESC")
    fun activeMemos(): Flow<List<ScheduleMemoEntity>>

    @Query("SELECT * FROM schedule_memos WHERE id = :id")
    suspend fun memoById(id: String): ScheduleMemoEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(memo: ScheduleMemoEntity)

    @Query("UPDATE schedule_memos SET trashedAt = :trashedAt, updatedAt = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: String, trashedAt: Long, updatedAt: Long)

    @Query("DELETE FROM schedule_memos WHERE id = :id")
    suspend fun permanentDelete(id: String)
}

@Dao
interface ScheduleEventDao {
    @Query("SELECT * FROM schedule_events ORDER BY startsAt ASC")
    fun all(): Flow<List<ScheduleEventEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(event: ScheduleEventEntity)

    @Query("DELETE FROM schedule_events WHERE id = :id")
    suspend fun delete(id: String)
}
