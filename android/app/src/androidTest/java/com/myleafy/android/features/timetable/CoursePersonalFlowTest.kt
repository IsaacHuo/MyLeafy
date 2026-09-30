package com.myleafy.android.features.timetable

import android.Manifest
import android.content.Context
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.core.data.local.*
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.features.timetable.presentation.CourseDetailSheet
import com.myleafy.android.ui.theme.MyLeafyTheme
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class CoursePersonalFlowTest {
    @get:Rule val compose = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val container get() = (context.applicationContext as MyLeafyApplication).container
    private val semester get() = SemesterConfig.currentSemesterId
    private fun course(scope: String) = CourseEntity(scope, "fixture-course", semester, "测试课程（仅自动化）", "测试教师", "", "", "测试教室", 1, (1..20).toList(), listOf(6, 7))

    @Test fun noteScopesSaveAndUnsavedExitRequiresConfirmation() {
        val scope = "fixture-note-flow"
        container.activeAppScopeStore.activateGuest(scope)
        val item = course(scope)
        var dismissed = false
        compose.setContent { MyLeafyTheme { CourseDetailSheet(item, 4, listOf(item), {}, { dismissed = true }) } }
        compose.waitUntil(10_000) { compose.onAllNodesWithText("保存备注").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("作业、考试、分组或老师要求").performTextInput("本次备注")
        compose.onNodeWithText("保存备注").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking { container.timetablePersonalDao.notes(scope, semester).first().any { it.week == 4 && it.text == "本次备注" } } }
        compose.onNodeWithText("所有这门课").performScrollTo().performClick()
        compose.onNodeWithText("作业、考试、分组或老师要求").performTextReplacement("整门课备注")
        compose.onNodeWithText("保存备注").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking { container.timetablePersonalDao.notes(scope, semester).first().size == 2 } }
        compose.onNodeWithText("作业、考试、分组或老师要求").performTextReplacement("未保存")
        compose.onNodeWithText("完成").performScrollTo().performClick()
        compose.onNodeWithText("放弃未保存的更改？").assertIsDisplayed()
        assertFalse(dismissed)
        compose.onNodeWithText("放弃更改").performClick()
        assertTrue(dismissed)
        runBlocking { assertTrue(container.timetablePersonalDao.notes("other-identity", semester).first().isEmpty()) }
    }

    @Test fun permissionsSchedulingRecoveryAndIdentityCancellationUseRealAlarmManager() = runBlocking {
        val scope = "fixture-reminder-flow"
        container.activeAppScopeStore.activateGuest(scope)
        val item = course(scope)
        container.courseDao.replaceForSemester(scope, semester, listOf(item))
        container.timetablePersonalDao.save(CourseReminderEntity(scope, semester, item.stableCourseKey(), 20, 6))
        fun shell(command: String) {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)).use { it.readBytes() }
        }
        val prefs = context.getSharedPreferences("course-alarm-delivery", Context.MODE_PRIVATE)
        shell("appops set ${context.packageName} POST_NOTIFICATION ignore")
        container.courseReminderScheduler.reconcile()
        assertNotNull(container.courseReminderScheduler.permissionProblem())
        assertTrue(prefs.getStringSet("scheduled", emptySet()).orEmpty().isEmpty())
        shell("pm grant ${context.packageName} ${Manifest.permission.POST_NOTIFICATIONS}")
        shell("appops set ${context.packageName} POST_NOTIFICATION allow")
        shell("appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow")
        assertNull(container.courseReminderScheduler.permissionProblem())
        container.courseReminderScheduler.reconcile()
        val ids = prefs.getStringSet("scheduled", emptySet()).orEmpty().toSet()
        assertTrue(ids.isNotEmpty())
        container.courseReminderScheduler.reconcile()
        assertEquals(ids, prefs.getStringSet("scheduled", emptySet()))
        container.activeAppScopeStore.activateGuest("fixture-other")
        container.courseReminderScheduler.reconcile()
        assertTrue(prefs.getStringSet("scheduled", emptySet()).orEmpty().isEmpty())
    }
}
