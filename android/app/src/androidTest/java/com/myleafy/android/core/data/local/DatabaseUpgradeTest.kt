package com.myleafy.android.core.data.local

import androidx.room.Room
import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DatabaseUpgradeTest {
    @get:Rule val helper = MigrationTestHelper(InstrumentationRegistry.getInstrumentation(), AppDatabase::class.java)

    @Test fun versionSevenPreservesEventsAndAddsPersonalCourseTables() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "isolated-schema-upgrade-test"
        helper.createDatabase(name, 7).apply {
            execSQL("INSERT INTO schedule_events(scopeKey,id,title,startsAt,endsAt,location,note,minutesBefore) VALUES('test','old','old',1,2,NULL,NULL,0)")
            execSQL("INSERT INTO courses VALUES('test','old','2026-2027-1','保留课程','教师','','','教室',1,'[1,2]','[6,7]')")
            execSQL("INSERT INTO schedule_memos VALUES('test','old','保留随记','memo',NULL,'[]',1,1,NULL,NULL,NULL,NULL)")
            close()
        }
        val database = Room.databaseBuilder(context, AppDatabase::class.java, name)
            .build()
        try {
            assertEquals(emptyList<GradeEntity>(), database.gradeDao().all("test").first())
            assertEquals("保留课程", database.courseDao().coursesForSemester("test", "2026-2027-1").first().single().courseName)
            database.openHelper.readableDatabase.query("SELECT body FROM schedule_memos").use {
                it.moveToFirst(); assertEquals("保留随记", it.getString(0))
            }
            database.openHelper.readableDatabase.query("SELECT COUNT(*) FROM schedule_events").use {
                it.moveToFirst(); assertEquals(1, it.getInt(0))
            }
            database.timetablePersonalDao().save(CourseNoteEntity("test", "2026-2027-1", "course", 0, "保留备注"))
            assertEquals("保留备注", database.timetablePersonalDao().notes("test", "2026-2027-1").first().single().text)
            database.gradeDao().upsertAll(listOf(GradeEntity("test", "new", "2026-2027-1", "课程", "3", "90", "必修", courseCode = "A")))
            assertEquals("A", database.gradeDao().all("test").first().single().courseCode)
        } finally { database.close(); context.deleteDatabase(name) }
    }
}
