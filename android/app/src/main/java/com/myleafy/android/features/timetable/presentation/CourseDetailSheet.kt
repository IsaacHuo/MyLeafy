package com.myleafy.android.features.timetable.presentation

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.foundation.clickable
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.core.data.local.*
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.ui.components.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import java.time.LocalDate

internal fun compactWeeks(weeks: List<Int>): String {
    val values = weeks.distinct().sorted()
    if (values.isEmpty()) return "未填写"
    val ranges = mutableListOf<String>()
    var start = values.first()
    var end = start
    fun append() { ranges += if (start == end) "$start" else "$start–$end" }
    for (week in values.drop(1)) if (week == end + 1) end = week else { append(); start = week; end = week }
    append()
    return "第${ranges.joinToString("、")}周"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CourseDetailSheet(course: CourseEntity, week: Int, courses: List<CourseEntity>, onTeacher: (String) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val container = (context.applicationContext as MyLeafyApplication).container
    val dao = container.timetablePersonalDao
    val key = course.stableCourseKey()
    val owner = rememberCoroutineScope()
    var error by remember { mutableStateOf<String?>(null) }
    var feedback by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val notes by remember(course.scopeKey, course.sourceSemesterID) {
        dao.notes(course.scopeKey, course.sourceSemesterID).catch { error = it.message ?: "备注读取失败" }
    }.collectAsStateWithLifecycle(initialValue = null)
    val reminders by remember(course.scopeKey, course.sourceSemesterID) {
        dao.reminders(course.scopeKey, course.sourceSemesterID).catch { error = it.message ?: "提醒读取失败" }
    }.collectAsStateWithLifecycle(initialValue = null)
    var noteWeek by rememberSaveable(key, week) { mutableIntStateOf(week) }
    var draft by rememberSaveable(key, week) { mutableStateOf("") }
    var edited by rememberSaveable(key, week) { mutableStateOf(false) }
    var pendingScope by remember { mutableStateOf<Int?>(null) }
    val savedNote = notes?.firstOrNull { it.courseKey == key && it.week == noteWeek }?.text.orEmpty()
    LaunchedEffect(savedNote, noteWeek) { if (!edited) draft = savedNote }
    val reminder = reminders?.firstOrNull { it.courseKey == key }
    var minutes by rememberSaveable(key) { mutableIntStateOf(0) }
    var custom by rememberSaveable(key) { mutableStateOf("20") }
    var anchor by rememberSaveable(key) { mutableIntStateOf(course.duration.minOrNull() ?: 1) }
    var selectingCustom by rememberSaveable(key) { mutableStateOf(false) }
    LaunchedEffect(reminder) { minutes = reminder?.minutes ?: 0; anchor = reminder?.anchorPeriod ?: (course.duration.minOrNull() ?: 1); custom = minutes.takeIf { it > 0 }?.toString() ?: "20"; selectingCustom = minutes !in listOf(0, 5, 20, 30) }
    val effectiveMinutes = if (selectingCustom) custom.toIntOrNull() else minutes
    val reminderDirty = reminders != null && (effectiveMinutes != (reminder?.minutes ?: 0) || (effectiveMinutes != 0 && anchor != (reminder?.anchorPeriod ?: (course.duration.minOrNull() ?: 1))))
    val noteDirty = edited && draft != savedNote
    val dirty = noteDirty || reminderDirty
    val requestExit = rememberEditorExit(dirty, saving, onDismiss)
    val currentDirty by rememberUpdatedState(dirty)
    val currentSaving by rememberUpdatedState(saving)
    val currentRequestExit by rememberUpdatedState(requestExit)
    // confirmValueChange is a SheetState identity key. Editing must not reset it to Hidden.
    val confirmSheetValueChange: (SheetValue) -> Boolean = remember {
        { value -> if (value == SheetValue.Hidden && (currentDirty || currentSaving)) { currentRequestExit(); false } else true }
    }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false, confirmValueChange = confirmSheetValueChange)
    val noteIntoView = remember { BringIntoViewRequester() }
    val reminderIntoView = remember { BringIntoViewRequester() }
    var focusedField by remember { mutableIntStateOf(0) }
    var permissionProblem by remember { mutableStateOf(container.courseReminderScheduler.permissionProblem()) }
    val schedulingError by container.courseReminderScheduler.error.collectAsStateWithLifecycle()
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        permissionProblem = container.courseReminderScheduler.permissionProblem()
        owner.launch { container.courseReminderScheduler.reconcile() }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        permissionProblem = container.courseReminderScheduler.permissionProblem()
        owner.launch { container.courseReminderScheduler.reconcile() }
    }
    fun mutate(block: suspend () -> Unit) {
        if (saving) return
        saving = true; error = null; feedback = null
        owner.launch {
            try {
                check(container.activeAppScopeStore.current.scopeKey == course.scopeKey) { "账号已切换，请重新打开课程" }
                block()
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { error = failure.message ?: "保存失败，请重试" }
            finally { saving = false }
        }
    }
    val occurrences = remember(courses, course.courseName) {
        courses.filter { it.sourceSemesterID == course.sourceSemesterID && it.courseName.trim().lowercase() == course.courseName.trim().lowercase() }
            .flatMap { item -> item.weeks.map { Triple(it, item.dayOfWeek, item.duration.minOrNull() ?: 1) } }
            .distinct().sortedWith(compareBy({ it.first }, { it.second }, { it.third }))
    }
    val occurrence = Triple(week, course.dayOfWeek, course.duration.minOrNull() ?: 1)
    val ordinal = occurrences.indexOf(occurrence) + 1
    val courseConfig = SemesterConfig.timelineConfigurations.firstOrNull { it.semesterId == course.sourceSemesterID }
    val date = courseConfig?.semesterStartDate?.plusWeeks((week - 1).toLong())?.plusDays((course.dayOfWeek - 1).toLong())
    LeafyModalBottomSheet(sheetState = sheetState, onDismissRequest = requestExit) {
        // ModalBottomSheet owns a separate window; observe its IME after the viewport resizes.
        val imeBottom = WindowInsets.ime.getBottom(LocalDensity.current)
        LaunchedEffect(focusedField, imeBottom) {
            if (focusedField != 0) {
                sheetState.expand()
                (if (focusedField == 1) noteIntoView else reminderIntoView).bringIntoView()
            }
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("课程详情", style = MaterialTheme.typography.titleLarge)
                LeafyTextButton(onClick = requestExit, enabled = !saving) { Text("完成") }
            }
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(course.courseName, style = MaterialTheme.typography.titleLarge)
                    Text(if (ordinal > 0) "第 $ordinal / ${occurrences.size} 次课 · 第 $week 周" else "第 $week 周", style = MaterialTheme.typography.bodyMedium)
                    if (occurrences.isNotEmpty()) LinearProgressIndicator(progress = { (ordinal.toFloat() / occurrences.size).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth())
                }
            }
            CourseDetailValue("教室", listOf(course.location, course.room).filter(String::isNotBlank).distinct().joinToString(" ").ifBlank { "未填写" })
            CourseDetailValue("节次", "${date ?: "学期日期未确认"} · ${courseTimeDescription(course)}")
            val teachers = course.teacher.split(Regex("[、,，;；/\\n]+")).map(String::trim).filter(String::isNotBlank).distinct()
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("教师", Modifier.width(44.dp), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                FlowRow(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (teachers.isEmpty()) Text("未填写", style = MaterialTheme.typography.bodyMedium)
                    else teachers.forEach { teacher ->
                        Text("$teacher ›", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.clickable(role = androidx.compose.ui.semantics.Role.Button) {
                                if (!dirty && !saving) onTeacher(teacher) else error = "请先保存或放弃更改"
                            })
                    }
                }
            }
            CourseDetailValue("周次", compactWeeks(course.weeks))
            if (course.classInfo.isNotBlank()) CourseDetailValue("班级", course.classInfo)
            HorizontalDivider()
            Text("课程备注", style = MaterialTheme.typography.titleMedium)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                listOf(week to "仅本次课", 0 to "所有这门课").forEachIndexed { index, (value, label) ->
                    SegmentedButton(selected = noteWeek == value, enabled = !saving && notes != null,
                        onClick = { if (value != noteWeek) { if (noteDirty) pendingScope = value else { edited = false; noteWeek = value } } },
                        shape = SegmentedButtonDefaults.itemShape(index, 2)) { Text(label) }
                }
            }
            LeafyTextField(value = draft, onValueChange = { draft = it; edited = true }, enabled = !saving && notes != null,
                label = { Text("作业、考试、分组或老师要求") }, minLines = 2, modifier = Modifier.fillMaxWidth().bringIntoViewRequester(noteIntoView).onFocusChanged { if (it.isFocused) focusedField = 1 else if (focusedField == 1) focusedField = 0 })
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LeafyPrimaryButton(enabled = !saving && notes != null, onClick = { mutate {
                    if (draft.isBlank()) dao.deleteNote(course.scopeKey, course.sourceSemesterID, key, noteWeek)
                    else dao.save(CourseNoteEntity(course.scopeKey, course.sourceSemesterID, key, noteWeek, draft.trim()))
                    edited = false; feedback = "备注已保存"
                } }) { Text(if (saving) "保存中…" else "保存备注") }
                if (savedNote.isNotEmpty()) LeafyTextButton(enabled = !saving, onClick = { mutate {
                    dao.deleteNote(course.scopeKey, course.sourceSemesterID, key, noteWeek); draft = ""; edited = false; feedback = "备注已删除"
                } }) { Text("删除备注") }
            }
            Text(if (noteWeek == 0) "适用于这门课的所有周次。" else "仅适用于本周这一次课。", style = MaterialTheme.typography.bodySmall)
            HorizontalDivider()
            Text("课前提醒", style = MaterialTheme.typography.titleMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(0, 5, 20, 30).forEach { value -> FilterChip(selected = !selectingCustom && minutes == value,
                    onClick = { minutes = value; selectingCustom = false }, enabled = !saving,
                    label = { Text(if (value == 0) "关闭" else "$value 分钟") }) }
                FilterChip(selected = selectingCustom, enabled = !saving, onClick = { selectingCustom = true }, label = { Text("自定义") })
            }
            if (selectingCustom) LeafyTextField(value = custom, onValueChange = { custom = it }, label = { Text("提前分钟数（1–180）") }, singleLine = true,
                isError = custom.toIntOrNull() !in 1..180, modifier = Modifier.fillMaxWidth().bringIntoViewRequester(reminderIntoView).onFocusChanged { if (it.isFocused) focusedField = 2 else if (focusedField == 2) focusedField = 0 })
            if (course.duration.size > 1 && (selectingCustom || minutes > 0)) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                course.duration.distinct().sorted().forEach { period -> FilterChip(selected = anchor == period, onClick = { anchor = period }, label = { Text("第 $period 节开始前") }) }
            }
            LeafyPrimaryButton(enabled = !saving && reminders != null && (!selectingCustom || custom.toIntOrNull() in 1..180), onClick = { mutate {
                dao.save(CourseReminderEntity(course.scopeKey, course.sourceSemesterID, key, if (selectingCustom) custom.toInt() else minutes, anchor))
                container.courseReminderScheduler.reconcile()
                permissionProblem = container.courseReminderScheduler.permissionProblem()
                feedback = if (!selectingCustom && minutes == 0) "提醒已关闭" else permissionProblem ?: container.courseReminderScheduler.error.value ?: "提醒已应用"
                if ((selectingCustom || minutes > 0) && Build.VERSION.SDK_INT >= 33 && !androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled())
                    notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            } }) { Text("应用提醒") }
            if (reminder != null && reminder.minutes > 0 && permissionProblem != null) {
                LeafyStatusBanner(permissionProblem!!, isError = true, actionLabel = "设置", onAction = {
                    val intent = if (Build.VERSION.SDK_INT >= 31 && !context.getSystemService(android.app.AlarmManager::class.java).canScheduleExactAlarms())
                        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))
                    else Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    context.startActivity(intent)
                })
            }
            Text("提醒只保存在本机，会为这门课尚未开始的周次创建本地通知。", style = MaterialTheme.typography.bodySmall)
            schedulingError?.let { LeafyStatusBanner(it, isError = true) }
            error?.let { LeafyStatusBanner(it, isError = true, onDismiss = { error = null }) }
            feedback?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            Spacer(Modifier.height(16.dp))
        }
    }
    pendingScope?.let { target -> LeafyAlertDialog(onDismissRequest = { pendingScope = null }, title = { Text("放弃未保存的更改？") },
        confirmButton = { LeafyTextButton(onClick = { edited = false; noteWeek = target; pendingScope = null }) { Text("放弃更改") } },
        dismissButton = { LeafyTextButton(onClick = { pendingScope = null }) { Text("继续编辑") } }) }
}

@Composable
private fun CourseDetailValue(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, Modifier.width(44.dp), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        Text(value, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PendingCoursePersonalSheet(onDismiss: () -> Unit) {
    val container = (LocalContext.current.applicationContext as MyLeafyApplication).container
    val identity by container.activeAppScopeStore.scope.collectAsStateWithLifecycle()
    val semester = SemesterConfig.currentSemesterId
    val dao = container.timetablePersonalDao
    var error by remember { mutableStateOf<String?>(null) }
    val notes by remember(identity.scopeKey, semester) { dao.notes(identity.scopeKey, semester).catch { error = it.message } }.collectAsStateWithLifecycle(emptyList())
    val reminders by remember(identity.scopeKey, semester) { dao.reminders(identity.scopeKey, semester).catch { error = it.message } }.collectAsStateWithLifecycle(emptyList())
    var deleting by remember { mutableStateOf<Any?>(null) }
    val owner = rememberCoroutineScope()
    LeafyModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("待关联备注与提醒", style = MaterialTheme.typography.titleLarge)
            Text("课程安排变更后无法确定对应课次的记录保留在这里；这些提醒不会发送。", style = MaterialTheme.typography.bodyMedium)
            notes.filter { it.orphaned }.forEach { note ->
                Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) {
                    Text(note.courseKey.split('|').getOrNull(1).orEmpty(), style = MaterialTheme.typography.titleMedium)
                    Text(if (note.week == 0) "所有这门课" else "第 ${note.week} 周")
                    Text(note.text)
                    LeafyTextButton(onClick = { deleting = note }) { Text("删除备注") }
                } }
            }
            reminders.filter { it.orphaned }.forEach { reminder ->
                Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) {
                    Text(reminder.courseKey.split('|').getOrNull(1).orEmpty(), style = MaterialTheme.typography.titleMedium)
                    Text("第 ${reminder.anchorPeriod} 节开始前 ${reminder.minutes} 分钟 · 未启用")
                    LeafyTextButton(onClick = { deleting = reminder }) { Text("删除提醒") }
                } }
            }
            if (notes.none { it.orphaned } && reminders.none { it.orphaned }) Text("没有待关联的记录")
            error?.let { LeafyStatusBanner(it, isError = true) }
            LeafyTextButton(onClick = onDismiss) { Text("完成") }
        }
    }
    deleting?.let { record -> LeafyAlertDialog(onDismissRequest = { deleting = null }, title = { Text("删除这条记录？") }, text = { Text("删除后无法恢复。") },
        confirmButton = { LeafyTextButton(onClick = { owner.launch {
            try {
                when (record) {
                    is CourseNoteEntity -> dao.deleteNote(record.scopeKey, record.semesterId, record.courseKey, record.week)
                    is CourseReminderEntity -> dao.deleteReminder(record.scopeKey, record.semesterId, record.courseKey)
                }
                deleting = null
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { error = failure.message ?: "删除失败，请重试" }
        } }) { Text("删除") } }, dismissButton = { LeafyTextButton(onClick = { deleting = null }) { Text("取消") } }) }
}
