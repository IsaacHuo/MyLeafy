package com.myleafy.android.features.campus

import androidx.room.Room
import androidx.test.platform.app.InstrumentationRegistry
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.data.local.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.LocalDate
import java.util.zip.ZipFile

class CampusFilesAndStorageTest {
    @Test fun medicalEditingKeepsPhotosAndChecksEveryStatusAndDeadline() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java).build()
        val scopes = ActiveAppScopeStore().apply { activateGuest("medical-edit-${java.util.UUID.randomUUID()}") }
        val repository = CampusLifeRepository(context, db.sportsDao(), db.medicalDao(), scopes)
        val today = LocalDate.of(2026, 10, 1)
        val policy = MedicalPolicy.load(context)
        val source = File(context.cacheDir, "medical-edit-test.png")
        val bitmap = android.graphics.Bitmap.createBitmap(32,32,android.graphics.Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.GREEN)
        source.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }; bitmap.recycle()
        var copied = emptyList<File>()
        try {
            val draft = MedicalLedgerDraft(visitDate=today,hospitalName="测试医院",department="科室",diagnosis="诊断",totalExpense=200.0,estimatedReimbursement=160.0,actualReimbursement=150.0,deadline=today.plusDays(14),materials=policy.materials.joinToString("|"),note="完整编辑")
            val id = repository.saveMedicalEntry(draft)
            val original = db.medicalDao().entries(scopes.current.scopeKey).first().single()
            repeat(2) { repository.importMedicalPhoto(id,android.net.Uri.fromFile(source)) }
            val photos = db.medicalDao().allPhotos(scopes.current.scopeKey).first()
            copied = photos.map { File(it.localFilename) }
            assertEquals(2, photos.size); assertTrue(copied.all { it.isFile })
            policy.statuses.forEach { status ->
                repository.saveMedicalEntry(draft.copy(id=id,status=status,hospitalName="编辑后的医院"))
                val edited = db.medicalDao().entries(scopes.current.scopeKey).first().single()
                assertEquals(original.createdAt,edited.createdAt); assertEquals(10,edited.materialChecklist.split('|').size)
                assertEquals(150.0,edited.actualReimbursement!!,0.0); assertEquals("诊断",edited.diagnosisNote)
                assertEquals(if(status in listOf("已报销","已归档")) "已结案" else "14 天内到期",medicalDeadline(edited,today))
                assertEquals(2,db.medicalDao().allPhotos(scopes.current.scopeKey).first().size)
            }
            assertEquals("已逾期 1 天",medicalDeadline(original.copy(reimbursementDeadline=today.minusDays(1).toEpochDay()),today))
            assertEquals("剩余 15 天",medicalDeadline(original.copy(reimbursementDeadline=today.plusDays(15).toEpochDay()),today))
            repository.deleteMedicalPhoto(photos.first()); assertFalse(copied.first().exists())
            repository.deleteMedicalEntry(db.medicalDao().entries(scopes.current.scopeKey).first().single())
            assertTrue(db.medicalDao().allPhotos(scopes.current.scopeKey).first().isEmpty()); assertTrue(copied.none { it.exists() })
        } finally { copied.forEach { it.delete() }; source.delete(); db.close() }
    }
    @Test fun medicalSnapshotAndVenuesHaveAllSourceContent() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val policy = MedicalPolicy.load(context)
        assertEquals(7, policy.scenarioAdvices.size); assertEquals(6,policy.statuses.size); assertEquals(10,policy.materials.size)
        assertTrue(policy.scenarioAdvices.all { it.steps.isNotEmpty() && it.materials.isNotEmpty() && it.notes.isNotEmpty() })
        assertTrue(policy.medicationRules.isNotEmpty()); assertTrue(policy.excludedExpenses.isNotEmpty()); assertTrue(policy.rehabRules.isNotEmpty())
        assertEquals(9,CampusVenueGroup.load(context).sumOf { it.venues.size })
        assertTrue(CampusVenueGroup.load(context).flatMap { it.venues }.all { it.details.isNotEmpty() && it.location.isNotBlank() })
    }
    @Test fun zipContainsStructuredRowsAndPhotosAndFailsForMissingAttachment() = runBlocking {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val database=Room.inMemoryDatabaseBuilder(context,AppDatabase::class.java).build()
        val scopes=ActiveAppScopeStore().apply { activateGuest("isolated-medical-export") }
        val repository=CampusLifeRepository(context,database.sportsDao(),database.medicalDao(),scopes)
        val photo=File(context.cacheDir,"isolated-medical-photo-test.jpg").apply { writeBytes(byteArrayOf(1,2,3)) }
        var zip:File?=null
        try {
            val id=repository.saveMedicalEntry(MedicalLedgerDraft(visitDate=LocalDate.of(2026,10,1),hospitalName="医院,一部",totalExpense=120.5,materials="门诊病历|处方",note="包含\"引号\"\n换行"))
            database.medicalDao().upsert(MedicalLedgerPhotoEntity("photo",scopes.current.scopeKey,id,"凭证.jpg",photo.absolutePath,1,1))
            val entries=database.medicalDao().entries(scopes.current.scopeKey).first()
            zip=repository.exportMedicalLedger(entries)
            ZipFile(zip).use { archive ->
                assertNotNull(archive.getEntry("medical-ledger.csv")); assertNotNull(archive.getEntry("photos/$id/${photo.name}"))
                val manifest=Json.parseToJsonElement(archive.getInputStream(archive.getEntry("manifest.json")).reader().readText()).jsonObject
                val row=manifest.getValue("entries").jsonArray.single().jsonObject
                assertEquals("医院,一部",row.getValue("hospitalName").jsonPrimitive.content); assertEquals(120.5,row.getValue("totalExpense").jsonPrimitive.double,0.0)
                assertEquals(listOf("门诊病历","处方"),row.getValue("materials").jsonArray.map { it.jsonPrimitive.content })
                val csv=archive.getInputStream(archive.getEntry("medical-ledger.csv")).reader().readText()
                assertTrue(csv.contains("\"医院,一部\"")); assertTrue(csv.contains("\"\"引号\"\""))
            }
            photo.delete()
            assertTrue(runCatching { repository.exportMedicalLedger(entries) }.exceptionOrNull()?.message.orEmpty().contains("缺失"))
            scopes.activateGuest("other")
            assertTrue(runCatching { repository.deleteMedicalEntry(entries.single()) }.isFailure)
            assertTrue(database.medicalDao().entries("other").first().isEmpty())
        } finally { zip?.delete(); photo.delete(); database.close() }
    }
    @Test fun collegeRecordsFavoritesEvidenceAndRemindersRemainScoped() = runBlocking {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val db=Room.inMemoryDatabaseBuilder(context,AppDatabase::class.java).build()
        try {
            val dao=db.comprehensiveQualityDao()
            fun record(college:String,value:Double)=ComprehensiveQualityRecordEntity("test","$college|2026届",college,"2026届",value,null,null,"","[]",1)
            dao.saveForCollege(record("园林学院",80.0)); dao.saveForCollege(record("信息学院",90.0))
            assertEquals(80.0,dao.current("test","园林学院").first()!!.academicStandardScore!!,0.0)
            assertEquals(90.0,dao.current("test","信息学院").first()!!.academicStandardScore!!,0.0); assertNull(dao.current("other","园林学院").first())
            db.campusPersonalDao().save(FavoriteClassroomEntity("test","二教","101",1)); assertTrue(db.campusPersonalDao().favorites("other").first().isEmpty())
            db.campusPersonalDao().save(SunshineReminderEntity("test")); assertFalse(db.campusPersonalDao().reminder("test").first()!!.enabled)
            db.campusPersonalDao().save(ComprehensiveEvidenceEntity("test","a","园林学院","2026届","SPORTS","材料.pdf","a.pdf","application/pdf",1))
            assertEquals(1,db.campusPersonalDao().evidence("test","园林学院","2026届").first().size); assertTrue(db.campusPersonalDao().evidence("test","信息学院","2026届").first().isEmpty())
        } finally { db.close() }
    }
    @Test fun csvValidationAndTransactionFailuresKeepOldGrades() = runBlocking {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val db=Room.inMemoryDatabaseBuilder(context,AppDatabase::class.java).build()
        try {
            val old=GradeEntity("test","old","term","原成绩","3","80","必修")
            db.gradeDao().upsertAll(listOf(old))
            assertTrue(runCatching { GuestAcademicCsv.parse("term,courseName,credit,score,type\nterm,,3,85,必修",GuestAcademicKind.GRADE) }.isFailure)
            assertEquals(listOf(old),db.gradeDao().all("test").first())
            db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_grade BEFORE INSERT ON grades WHEN NEW.courseName = '失败' BEGIN SELECT RAISE(ABORT, 'test failure'); END")
            assertTrue(runCatching { db.gradeDao().replaceAll("test",listOf(old.copy(courseName="失败"))) }.isFailure)
            assertEquals(listOf(old),db.gradeDao().all("test").first())
        } finally { db.close() }
    }
    @Test fun sunshineRemindersCancelAfterCompletionDisableAndIdentityChange() = runBlocking {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val context=instrumentation.targetContext
        fun shell(command:String) { android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).use { it.readBytes() } }
        shell("pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS")
        shell("appops set ${context.packageName} POST_NOTIFICATION allow")
        val db=Room.inMemoryDatabaseBuilder(context,AppDatabase::class.java).build()
        val scopes=ActiveAppScopeStore().apply { activateGuest("sunshine-reminder-test") }
        val repository=CampusLifeRepository(context,db.sportsDao(),db.medicalDao(),scopes)
        val scheduler=SunshineReminderScheduler(context,scopes,db.campusPersonalDao(),repository)
        val preferences=context.getSharedPreferences("sunshine-reminder-delivery",android.content.Context.MODE_PRIVATE)
        try {
            val config=com.myleafy.android.features.timetable.domain.SemesterConfig.current
            val today=LocalDate.now(java.time.ZoneId.of("Asia/Shanghai"))
            org.junit.Assume.assumeTrue(today >= config.semesterStartDate && today < SunshineRunPlanner.semesterEnd(config).minusDays(14))
            repository.saveSunshineSettings(34,8,1,"",false)
            val reminder=SunshineReminderEntity(scopes.current.scopeKey,true,"1,2,3,4,5,6,7",20,0)
            db.campusPersonalDao().save(reminder); scheduler.reconcile()
            val scheduled=preferences.getStringSet("scheduled",emptySet()).orEmpty().toSet()
            assertTrue(scheduled.isNotEmpty())
            val recovered=SunshineReminderScheduler(context,scopes,db.campusPersonalDao(),repository)
            recovered.reconcile(); assertEquals(scheduled,preferences.getStringSet("scheduled",emptySet()))
            val period=SunshineRunPlanner.period(today,SunshineRunPlanner.periods(emptyList(),repository.sunshineSettings.first(),config),config)!!
            repository.saveRun(today,period.weeks.first(),period.weeks.last()); scheduler.reconcile()
            assertTrue(preferences.getStringSet("scheduled",emptySet()).orEmpty().none { it.endsWith(":$today") })
            db.campusPersonalDao().save(reminder.copy(enabled=false)); scheduler.reconcile()
            assertTrue(preferences.getStringSet("scheduled",emptySet()).orEmpty().isEmpty())
            scopes.activateGuest("other-reminder-test"); scheduler.reconcile()
            assertTrue(preferences.getStringSet("scheduled",emptySet()).orEmpty().isEmpty())
        } finally { db.close() }
    }

}
