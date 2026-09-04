package com.myleafy.android.core.data.local

import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class Migration4To5Test {
    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java,
    )

    @Test
    fun migrationPreservesExistingScheduleAndCreatesScopedFeatureTables() {
        helper.createDatabase(DATABASE, 4).apply {
            execSQL(
                "INSERT INTO schedule_events(scopeKey,id,title,startsAt,endsAt,location,note,minutesBefore) VALUES(?,?,?,?,?,?,?,?)",
                arrayOf<Any?>("scope-a", "event-old", "迁移前日程", 1000L, 2000L, null, null, 0),
            )
            close()
        }

        helper.runMigrationsAndValidate(DATABASE, 5, true, MIGRATION_4_5).use { database ->
            database.query("SELECT title FROM schedule_events WHERE scopeKey='scope-a' AND id='event-old'").use {
                check(it.moveToFirst())
                assertEquals("迁移前日程", it.getString(0))
            }
            database.execSQL(
                "INSERT INTO fitness_test_records(id,scopeKey,testedAt,item,value,unit,note,createdAt,updatedAt) VALUES(?,?,?,?,?,?,?,?,?)",
                arrayOf<Any?>("fitness-a", "scope-a", 1L, "肺活量", 4200.0, "ml", "", 1L, 1L),
            )
            database.query("SELECT count(*) FROM fitness_test_records WHERE scopeKey='scope-b'").use {
                check(it.moveToFirst())
                assertEquals(0, it.getInt(0))
            }
        }
    }

    private companion object { const val DATABASE = "migration-4-5-test" }
}
