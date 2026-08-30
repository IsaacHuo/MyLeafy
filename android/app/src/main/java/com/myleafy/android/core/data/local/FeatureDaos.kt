package com.myleafy.android.core.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface GradeDao {
    @Query("SELECT * FROM grades WHERE scopeKey = :scopeKey ORDER BY term DESC, courseName")
    fun all(scopeKey: String): Flow<List<GradeEntity>>

    @Query("SELECT * FROM grades WHERE scopeKey = :scopeKey AND term = :term ORDER BY courseName")
    fun gradesForTerm(scopeKey: String, term: String): Flow<List<GradeEntity>>

    @Query("SELECT DISTINCT term FROM grades WHERE scopeKey = :scopeKey ORDER BY term DESC")
    fun availableTerms(scopeKey: String): Flow<List<String>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(grades: List<GradeEntity>)

    @Query("DELETE FROM grades WHERE scopeKey = :scopeKey")
    suspend fun clearAll(scopeKey: String)
}

@Dao
interface GradeRankingDao {
    @Query("SELECT * FROM grade_rankings WHERE scopeKey = :scopeKey ORDER BY term DESC, rankingRange")
    fun all(scopeKey: String): Flow<List<GradeRankingEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(rankings: List<GradeRankingEntity>)

    @Query("DELETE FROM grade_rankings WHERE scopeKey = :scopeKey")
    suspend fun clearAll(scopeKey: String)
}

@Dao
interface GradeSummaryDao {
    @Query("SELECT * FROM grade_summaries WHERE scopeKey = :scopeKey AND id = 'official' LIMIT 1")
    fun official(scopeKey: String): Flow<GradeSummaryEntity?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(summary: GradeSummaryEntity)
}

@Dao
interface ExamDao {
    @Query("SELECT * FROM exams WHERE scopeKey = :scopeKey ORDER BY date, start")
    fun all(scopeKey: String): Flow<List<ExamEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(exams: List<ExamEntity>)

    @Query("DELETE FROM exams WHERE scopeKey = :scopeKey")
    suspend fun clearAll(scopeKey: String)
}

@Dao
interface ScheduleMemoDao {
    @Query("SELECT * FROM schedule_memos WHERE scopeKey = :scopeKey AND trashedAt IS NULL ORDER BY pinnedAt DESC, updatedAt DESC")
    fun activeMemos(scopeKey: String): Flow<List<ScheduleMemoEntity>>

    @Query("SELECT * FROM schedule_memos WHERE scopeKey = :scopeKey AND id = :id")
    suspend fun memoById(scopeKey: String, id: String): ScheduleMemoEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(memo: ScheduleMemoEntity)

    @Query("UPDATE schedule_memos SET trashedAt = :trashedAt, updatedAt = :updatedAt WHERE scopeKey = :scopeKey AND id = :id")
    suspend fun softDelete(scopeKey: String, id: String, trashedAt: Long, updatedAt: Long)

    @Query("DELETE FROM schedule_memos WHERE scopeKey = :scopeKey AND id = :id")
    suspend fun permanentDelete(scopeKey: String, id: String)
}

@Dao
interface ScheduleEventDao {
    @Query("SELECT * FROM schedule_events WHERE scopeKey = :scopeKey ORDER BY startsAt ASC")
    fun all(scopeKey: String): Flow<List<ScheduleEventEntity>>

    @Query(
        """SELECT * FROM schedule_events
        WHERE scopeKey = :scopeKey
          AND startsAt < :endExclusive
          AND COALESCE(endsAt, startsAt + 1) > :startInclusive
        ORDER BY startsAt ASC""",
    )
    fun inRange(
        scopeKey: String,
        startInclusive: Long,
        endExclusive: Long,
    ): Flow<List<ScheduleEventEntity>>

    @Query("SELECT * FROM schedule_events WHERE scopeKey = :scopeKey AND id = :id LIMIT 1")
    suspend fun byId(scopeKey: String, id: String): ScheduleEventEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(event: ScheduleEventEntity)

    @Query("DELETE FROM schedule_events WHERE scopeKey = :scopeKey AND id = :id")
    suspend fun delete(scopeKey: String, id: String)
}
