package com.myleafy.android.core.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ScopedRoomIsolationTest {
    private lateinit var database: AppDatabase

    @Before
    fun createDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
    }

    @After
    fun closeDatabase() {
        database.close()
    }

    @Test
    fun identicalCourseIdsRemainIsolatedByScope() = runBlocking {
        val first = course(scopeKey = "scope-a", name = "森林生态学")
        val second = course(scopeKey = "scope-b", name = "数据结构")
        database.courseDao().upsertAll(listOf(first, second))

        assertEquals(
            listOf("森林生态学"),
            database.courseDao().coursesForSemester("scope-a", TERM).first().map { it.courseName },
        )
        assertEquals(
            listOf("数据结构"),
            database.courseDao().coursesForSemester("scope-b", TERM).first().map { it.courseName },
        )

        database.courseDao().clearForSemester("scope-a", TERM)

        assertEquals(emptyList<CourseEntity>(), database.courseDao().coursesForSemester("scope-a", TERM).first())
        assertEquals(1, database.courseDao().coursesForSemester("scope-b", TERM).first().size)
    }

    private fun course(scopeKey: String, name: String) = CourseEntity(
        scopeKey = scopeKey,
        id = "shared-course-id",
        sourceSemesterID = TERM,
        courseName = name,
        teacher = "教师",
        classInfo = "",
        room = "101",
        location = "一教",
        dayOfWeek = 1,
        weeks = listOf(1),
        duration = listOf(1, 2),
    )

    private companion object {
        const val TERM = "2026-2027-1"
    }
}
