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
    @Test fun versionEightPreservesAccountsNotesAndMedicalAttachmentsWithoutInventingCredits() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "isolated-v8-v9-parity-test"
        val photo = java.io.File(context.cacheDir, "migration-v8-photo.jpg").apply { writeBytes(byteArrayOf(1,2,3)) }
        helper.createDatabase(name, 8).apply {
            execSQL("INSERT INTO grade_summaries VALUES('account-a','official',3.2,85,NULL)")
            execSQL("INSERT INTO courses VALUES('account-a','course','2026-2027-1','保留课程','教师','','','教室',1,'[1,2]','[6,7]')")
            execSQL("INSERT INTO courses VALUES('account-b','course','2026-2027-1','另一账号课程','教师','','','教室',1,'[1,2]','[6,7]')")
            execSQL("INSERT INTO course_notes(scopeKey,semesterId,courseKey,week,text,orphaned) VALUES('account-a','2026-2027-1','course',0,'保留备注',0)")
            execSQL("INSERT INTO medical_ledger_photos VALUES('photo','account-a','entry','照片.jpg','${photo.absolutePath.replace("'", "''")}',1,1)")
            close()
        }
        val db = Room.databaseBuilder(context, AppDatabase::class.java, name).build()
        try {
            val summary = db.gradeSummaryDao().official("account-a").first()!!
            assertEquals(3.2, summary.officialGpa!!, 0.0); org.junit.Assert.assertNull(summary.totalCredits); org.junit.Assert.assertNull(summary.publicElectiveCredits)
            assertEquals("保留课程", db.courseDao().coursesForSemester("account-a", "2026-2027-1").first().single().courseName)
            assertEquals("另一账号课程", db.courseDao().coursesForSemester("account-b", "2026-2027-1").first().single().courseName)
            assertEquals("保留备注", db.timetablePersonalDao().notes("account-a", "2026-2027-1").first().single().text)
            assertEquals(photo.absolutePath, db.medicalDao().allPhotos("account-a").first().single().localFilename)
            org.junit.Assert.assertTrue(photo.isFile)
            assertEquals(emptyList<FavoriteClassroomEntity>(), db.campusPersonalDao().favorites("account-a").first())
            org.junit.Assert.assertNull(db.campusPersonalDao().reminder("account-a").first())
        } finally { db.close(); context.deleteDatabase(name); photo.delete() }
    }

}
