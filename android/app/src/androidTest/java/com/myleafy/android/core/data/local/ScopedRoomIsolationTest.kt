package com.myleafy.android.core.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

    @Test
    fun scheduleEventsSupportScopedCrudAndOverlappingRanges() = runBlocking {
        val dao = database.scheduleEventDao()
        val sharedA = scheduleEvent("scope-a", "shared", 1_100, 1_200, "A 日程")
        val sharedB = scheduleEvent("scope-b", "shared", 1_300, 1_400, "B 日程")
        dao.upsert(sharedA)
        dao.upsert(sharedB)
        dao.upsert(scheduleEvent("scope-a", "ends-at-start", 500, 1_000, "范围外"))
        dao.upsert(scheduleEvent("scope-a", "overlaps-start", 500, 1_001, "跨越起点"))
        dao.upsert(scheduleEvent("scope-a", "overlaps-end", 1_999, 2_500, "跨越终点"))
        dao.upsert(scheduleEvent("scope-a", "starts-at-end", 2_000, 2_100, "范围外"))

        assertEquals("A 日程", dao.byId("scope-a", "shared")?.title)
        assertEquals("B 日程", dao.byId("scope-b", "shared")?.title)
        assertEquals(
            listOf("跨越起点", "A 日程", "跨越终点"),
            dao.inRange("scope-a", 1_000, 2_000).first().map(ScheduleEventEntity::title),
        )

        dao.delete("scope-a", "shared")

        assertNull(dao.byId("scope-a", "shared"))
        assertEquals("B 日程", dao.byId("scope-b", "shared")?.title)
    }

    @Test
    fun scheduleEventsSurviveDatabaseReopen() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase(REOPEN_DATABASE)
        var fileDatabase = Room.databaseBuilder(context, AppDatabase::class.java, REOPEN_DATABASE).build()
        try {
            fileDatabase.scheduleEventDao().upsert(
                scheduleEvent("scope-a", "persisted", 1_100, 1_200, "重启后仍存在"),
            )
            fileDatabase.close()

            fileDatabase = Room.databaseBuilder(context, AppDatabase::class.java, REOPEN_DATABASE).build()
            assertEquals(
                "重启后仍存在",
                fileDatabase.scheduleEventDao().byId("scope-a", "persisted")?.title,
            )
        } finally {
            if (fileDatabase.isOpen) fileDatabase.close()
            context.deleteDatabase(REOPEN_DATABASE)
        }
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

    private fun scheduleEvent(
        scopeKey: String,
        id: String,
        startsAt: Long,
        endsAt: Long,
        title: String,
    ) = ScheduleEventEntity(
        scopeKey = scopeKey,
        id = id,
        title = title,
        startsAt = startsAt,
        endsAt = endsAt,
        location = null,
        note = null,
        minutesBefore = 0,
    )

    private companion object {
        const val TERM = "2026-2027-1"
        const val REOPEN_DATABASE = "scoped-room-reopen-test.db"
    }
}
