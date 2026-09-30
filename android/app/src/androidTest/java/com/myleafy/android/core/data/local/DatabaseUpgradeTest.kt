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

    @Test fun previousSchemaIsRebuiltWithoutTouchingOtherDatabases() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "isolated-schema-upgrade-test"
        helper.createDatabase(name, 6).apply {
            execSQL("INSERT INTO schedule_events(scopeKey,id,title,startsAt,endsAt,location,note,minutesBefore) VALUES('test','old','old',1,2,NULL,NULL,0)")
            close()
        }
        val database = Room.databaseBuilder(context, AppDatabase::class.java, name)
            .fallbackToDestructiveMigration(dropAllTables = true).build()
        try {
            assertEquals(emptyList<GradeEntity>(), database.gradeDao().all("test").first())
            database.openHelper.readableDatabase.query("SELECT COUNT(*) FROM schedule_events").use {
                it.moveToFirst(); assertEquals(0, it.getInt(0))
            }
            database.gradeDao().upsertAll(listOf(GradeEntity("test", "new", "2026-2027-1", "课程", "3", "90", "必修", courseCode = "A")))
            assertEquals("A", database.gradeDao().all("test").first().single().courseCode)
        } finally { database.close(); context.deleteDatabase(name) }
    }
}
