package com.myleafy.android.core.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface CourseDao {
    @Query("SELECT * FROM courses WHERE scopeKey = :scopeKey AND sourceSemesterID = :semesterId")
    fun coursesForSemester(scopeKey: String, semesterId: String): Flow<List<CourseEntity>>

    @Query("SELECT * FROM courses WHERE scopeKey = :scopeKey AND sourceSemesterID = :semesterId AND dayOfWeek = :dayOfWeek")
    fun coursesForDay(scopeKey: String, semesterId: String, dayOfWeek: Int): Flow<List<CourseEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(courses: List<CourseEntity>)

    @Query("DELETE FROM courses WHERE scopeKey = :scopeKey AND sourceSemesterID = :semesterId")
    suspend fun clearForSemester(scopeKey: String, semesterId: String)
}
