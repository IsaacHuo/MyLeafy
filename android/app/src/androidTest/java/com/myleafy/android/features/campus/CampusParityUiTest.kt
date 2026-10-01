package com.myleafy.android.features.campus

import android.graphics.Bitmap
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.myleafy.android.parsers.*
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.theme.MyLeafyTheme
import org.junit.Rule
import org.junit.Test
import java.io.File

class CampusParityUiTest {
    @get:Rule val compose=createComposeRule()
    private fun capture(name:String) {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val directory=File(context.getExternalFilesDir(null),"campus-parity").apply { mkdirs() }
        compose.onRoot().captureToImage().asAndroidBitmap().let { bitmap ->
            File(directory,"$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }

        }
    }
    @Test fun pdfPreviewLoadsBothPagesAndMissingFileShowsError() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val file=File(context.cacheDir,"parity-preview.pdf")
        val document=android.graphics.pdf.PdfDocument()
        try {
            repeat(2) { index ->
                val page=document.startPage(android.graphics.pdf.PdfDocument.PageInfo.Builder(200,300,index+1).create())
                page.canvas.drawText("Page ${index+1}",20f,40f,android.graphics.Paint().apply { textSize=20f })
                document.finishPage(page)
            }
            file.outputStream().use(document::writeTo)
        } finally { document.close() }
        var preview by mutableStateOf(file)
        try {
            compose.setContent { MyLeafyTheme { key(preview) { CampusFilePreview(preview,"application/pdf",{}) } } }
            compose.waitUntil(5_000) { compose.onAllNodesWithText("1 / 2").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("下一页").performClick()
            compose.onNodeWithText("2 / 2").assertIsDisplayed()
            compose.onNodeWithText("分享原文件").assertIsDisplayed()
            compose.runOnIdle { preview=File(context.cacheDir,"missing-parity.pdf") }
            compose.waitUntil(5_000) { compose.onAllNodesWithText("文件已丢失").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("文件已丢失").assertIsDisplayed()
        } finally { file.delete() }
    }
    @Test fun fullMedicalPolicyAndEveryScenarioAreReachableInDarkLargeFont() {
        var guide by mutableStateOf(false)
        compose.setContent {
            androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(androidx.compose.ui.platform.LocalDensity.current.density,1.5f)) {
                MyLeafyTheme(darkTheme=true) { LeafySecondaryScaffold("医疗事项",{}) { if (guide) MedicalGuideContent(it.padding(horizontal=20.dp)) else MedicalPolicyContent(it.padding(horizontal=20.dp)) } }
            }
        }
        compose.onNodeWithText("查看政策出处").assertIsDisplayed()
        capture("medical-policy-dark-large")
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("物理与康复治疗"))
        compose.onNodeWithText("物理与康复治疗").assertIsDisplayed()
        compose.runOnIdle { guide=true }
        val policy=MedicalPolicy.load(InstrumentationRegistry.getInstrumentation().targetContext)
        policy.scenarioAdvices.forEach { advice ->
            compose.onNode(hasScrollAction()).performScrollToNode(hasText(advice.id,substring=false) and hasClickAction())
            compose.onNode(hasText(advice.id,substring=false) and hasClickAction()).performClick()
            compose.onNode(hasScrollAction()).performScrollToNode(hasText("材料清单"))
            compose.onNodeWithText("材料清单").assertIsDisplayed()
            compose.onNode(hasScrollAction()).performScrollToNode(hasText("注意事项"))
            compose.onNodeWithText("注意事项").assertIsDisplayed()
        }
        capture("medical-scenario-dark-large")
    }
    @Test fun classroomSinglePeriodAndSpecifiedRoomShowDistinctStates() {
        val rows=listOf(ClassroomAvailabilityRow(EmptyClassroom("二教","101"),(1..12).map { ClassroomSlot(it,when(it) { 2 -> ClassroomStatus.OCCUPIED; 4 -> ClassroomStatus.UNKNOWN; else -> ClassroomStatus.AVAILABLE }) }),ClassroomAvailabilityRow(EmptyClassroom("二教","102"),(1..12).map { ClassroomSlot(it,ClassroomStatus.AVAILABLE) }))
        val repository=object:ClassroomRepository {
            override suspend fun emptyClassrooms(semesterId:String,week:Int,day:Int,startPeriod:Int,endPeriod:Int)=ClassroomAvailability((1..12).toList(),rows).available(startPeriod,endPeriod)
            override suspend fun availability(semesterId:String,week:Int,day:Int)=ClassroomAvailability((1..12).toList(),rows)
        }
        val model=ClassroomViewModel(repository)
        compose.setContent { MyLeafyTheme { ClassroomScreen({},model) } }
        compose.onNodeWithText("查询").performClick()
        compose.waitUntil(5000) { compose.onAllNodesWithText("共 2 间空闲教室").fetchSemanticsNodes().isNotEmpty() }
        capture("classrooms-single")
        compose.onNodeWithText("按教室").performClick()
        compose.onNodeWithText("二教",substring=false).performClick()
        compose.onNodeWithText("教室号").performTextInput("101")
        compose.onNodeWithText("查询").performScrollTo().performClick()
        compose.waitUntil(5000) { compose.onAllNodesWithText("占用",substring=false).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("占用",substring=false).performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("待确认",substring=false).performScrollTo().assertIsDisplayed()
        capture("classrooms-room-day")
    }
    @Test fun allVenueRegionsExpandAndKeepFullInformation() {
        compose.setContent { MyLeafyTheme { VenueOpeningsScreen({}) } }
        val groups=CampusVenueGroup.load(InstrumentationRegistry.getInstrumentation().targetContext)
        groups.forEach { group ->
            compose.onNode(hasScrollAction()).performScrollToNode(hasText(group.title,substring=true))
            compose.onNodeWithText(group.title,substring=true).performClick()
            group.venues.forEach { venue -> compose.onNode(hasScrollAction()).performScrollToNode(hasText(venue.title,substring=true)); compose.onNodeWithText(venue.title,substring=true).assertIsDisplayed().performClick() }
        }
        capture("sports-venues")
    }
    @Test fun graduationProgressRecomputesAndTeachingCoursesExpand() = kotlinx.coroutines.runBlocking {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val db=androidx.room.Room.inMemoryDatabaseBuilder(context,com.myleafy.android.core.data.local.AppDatabase::class.java).build()
        val scopes=com.myleafy.android.core.campus.ActiveAppScopeStore().apply { activateGuest("training-ui") }
        val program=ParsedTrainingProgram("测试专业本科培养方案",listOf(ParsedTrainingProgramSection("一、培养目标","完整培养正文",emptyList())),emptyList(),listOf(ParsedGraduationCreditRequirement("总学分",167.0,true),ParsedGraduationCreditRequirement("公共选修",8.5,false)))
        val plan=listOf(ParsedTeachingPlanSection("2026-2027-1",listOf(ParsedTeachingPlanCourse("CODE","森林生态学","林学院","3","48","必修","专业核心课","考试"))))
        db.academicDocumentDao().upsert(com.myleafy.android.core.data.local.AcademicDocumentEntity(scopes.current.scopeKey,"trainingProgram",kotlinx.serialization.json.Json.encodeToString(ParsedTrainingProgram.serializer(),program),1))
        db.academicDocumentDao().upsert(com.myleafy.android.core.data.local.AcademicDocumentEntity(scopes.current.scopeKey,"teachingPlan",kotlinx.serialization.json.Json.encodeToString(kotlinx.serialization.builtins.ListSerializer(ParsedTeachingPlanSection.serializer()),plan),1))
        val summary=kotlinx.coroutines.flow.MutableStateFlow<com.myleafy.android.core.data.local.GradeSummaryEntity?>(com.myleafy.android.core.data.local.GradeSummaryEntity("training-ui",officialGpa=null,officialWeightedAverage=null,officialCreditPoint=null,totalCredits=140.0,publicElectiveCredits=0.0))
        val client=java.lang.reflect.Proxy.newProxyInstance(com.myleafy.android.core.network.SchoolNetworkClient::class.java.classLoader,arrayOf(com.myleafy.android.core.network.SchoolNetworkClient::class.java)) { _,method,_ -> error("Unexpected network call ${method.name}") } as com.myleafy.android.core.network.SchoolNetworkClient
        val academic=java.lang.reflect.Proxy.newProxyInstance(AcademicRepository::class.java.classLoader,arrayOf(AcademicRepository::class.java)) { _,method,_ -> if(method.name=="gradeSummary") summary else kotlinx.coroutines.flow.flowOf(emptyList<Any>()) } as AcademicRepository
        val model=TrainingProgramViewModel(AcademicDocumentRepository(client,db.academicDocumentDao(),scopes),academic)
        try {
            compose.setContent { MyLeafyTheme { TrainingProgramScreen({},model) } }
            compose.waitUntil(5000) { compose.onAllNodesWithText("毕业进度").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("140 / 167 学分").assertIsDisplayed(); capture("graduation-progress")
            summary.value=summary.value!!.copy(totalCredits=0.0)
            compose.waitUntil(5000) { compose.onAllNodesWithText("0 / 167 学分").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("教学计划").performClick()
            compose.onNodeWithText("2026-2027-1",substring=true).performClick()
            compose.onNodeWithText("森林生态学").assertIsDisplayed()
            capture("teaching-plan")
        } finally { db.close() }
    }

}
