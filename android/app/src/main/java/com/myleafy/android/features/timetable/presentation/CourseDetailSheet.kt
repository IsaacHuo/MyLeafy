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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.School
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.foundation.clickable
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
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

/** 课程详情的窄依赖；默认从组合根取，截图/单测可以传入替身。 */
data class CourseDetailDependencies(
    val personalDao: com.myleafy.android.core.data.local.TimetablePersonalDao,
    val reminderScheduler: com.myleafy.android.features.timetable.CourseReminderScheduler,
    val currentScopeKey: () -> String,
)

@Composable
private fun rememberCourseDetailDependencies(): CourseDetailDependencies {
    val container = (LocalContext.current.applicationContext as MyLeafyApplication).container
    return remember(container) {
        CourseDetailDependencies(
            personalDao = container.timetablePersonalDao,
            reminderScheduler = container.courseReminderScheduler,
            currentScopeKey = { container.activeAppScopeStore.current.scopeKey },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CourseDetailSheet(
    course: CourseEntity,
    week: Int,
    courses: List<CourseEntity>,
    onTeacher: (String) -> Unit,
    onDismiss: () -> Unit,
    dependencies: CourseDetailDependencies = rememberCourseDetailDependencies(),
) {
    val context = LocalContext.current
    val dao = dependencies.personalDao
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
    var permissionProblem by remember { mutableStateOf(dependencies.reminderScheduler.permissionProblem()) }
    val schedulingError by dependencies.reminderScheduler.error.collectAsStateWithLifecycle()
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        permissionProblem = dependencies.reminderScheduler.permissionProblem()
        owner.launch { dependencies.reminderScheduler.reconcile() }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        permissionProblem = dependencies.reminderScheduler.permissionProblem()
        owner.launch { dependencies.reminderScheduler.reconcile() }
    }
    fun mutate(block: suspend () -> Unit) {
        if (saving) return
        saving = true; error = null; feedback = null
        owner.launch {
            try {
                check(dependencies.currentScopeKey() == course.scopeKey) { "账号已切换，请重新打开课程" }
                block()
            } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message ?: "保存失败，请重试" } finally { saving = false }
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
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("课程详情", style = MaterialTheme.typography.titleLarge)
                LeafyTextButton(onClick = requestExit, enabled = !saving) { Text("完成") }
            }
            LeafyContentSurface(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(course.courseName, style = MaterialTheme.typography.titleLarge)
                    Text(
                        text = if (ordinal > 0) "第 $ordinal / ${occurrences.size} 次课 · 第 $week 周" else "第 $week 周",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (occurrences.isNotEmpty()) {
                        LinearProgressIndicator(
                            progress = { (ordinal.toFloat() / occurrences.size).coerceIn(0f, 1f) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
            LeafyContentSurface(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                    CourseDetailInfoRow(
                        icon = Icons.Outlined.Place,
                        label = "教室",
                        value = listOf(course.location, course.room).filter(String::isNotBlank).distinct().joinToString(" ").ifBlank { "未填写" },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                    CourseDetailInfoRow(
                        icon = Icons.Outlined.Schedule,
                        label = "节次",
                        value = "${date ?: "学期日期未确认"} · ${courseTimeDescription(course)}",
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                    val teachers = course.teacher.split(Regex("[、,，;；/\\n]+")).map(String::trim).filter(String::isNotBlank).distinct()
                    if (teachers.isEmpty()) {
                        CourseDetailInfoRow(icon = Icons.Outlined.Person, label = "教师", value = "未填写")
                    } else {
                        teachers.forEach { teacher ->
                            CourseDetailInfoRow(
                                icon = Icons.Outlined.Person,
                                label = "教师",
                                value = teacher,
                                trailing = {
                                    Icon(
                                        Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(18.dp),
                                    )
                                },
                                onClick = {
                                    if (!dirty && !saving) onTeacher(teacher) else error = "请先保存或放弃更改"
                                },
                            )
                        }
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                    CourseDetailInfoRow(icon = Icons.Outlined.CalendarMonth, label = "周次", value = compactWeeks(course.weeks))
                    if (course.classInfo.isNotBlank()) {
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                        CourseDetailInfoRow(icon = Icons.Outlined.School, label = "班级", value = course.classInfo)
                    }
                }
            }
            LeafyContentSurface(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("课程备注", style = MaterialTheme.typography.titleMedium)
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        listOf(week to "仅本次课", 0 to "所有这门课").forEachIndexed { index, (value, label) ->
                            SegmentedButton(
                                selected = noteWeek == value,
                                enabled = !saving && notes != null,
                                onClick = {
                                    if (value != noteWeek) {
                                        if (noteDirty) pendingScope = value else {
                                            edited = false
                                            noteWeek = value
                                        }
                                    }
                                },
                                shape = SegmentedButtonDefaults.itemShape(index, 2),
                            ) { Text(label) }
                        }
                    }
                    LeafyTextField(
                        value = draft,
                        onValueChange = { draft = it; edited = true },
                        enabled = !saving && notes != null,
                        label = { Text("作业、考试、分组或老师要求") },
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth().bringIntoViewRequester(noteIntoView).onFocusChanged {
                            if (it.isFocused) focusedField = 1 else if (focusedField == 1) focusedField = 0
                        },
                    )
                    LeafyPrimaryButton(
                        enabled = !saving && notes != null,
                        modifier = Modifier.fillMaxWidth(),
                        onClick = {
                            mutate {
                                if (draft.isBlank()) dao.deleteNote(course.scopeKey, course.sourceSemesterID, key, noteWeek)
                                else dao.save(CourseNoteEntity(course.scopeKey, course.sourceSemesterID, key, noteWeek, draft.trim()))
                                edited = false
                                feedback = "备注已保存"
                            }
                        },
                    ) { Text(if (saving) "保存中…" else "保存备注") }
                    if (savedNote.isNotEmpty()) {
                        LeafyTextButton(
                            enabled = !saving,
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                mutate {
                                    dao.deleteNote(course.scopeKey, course.sourceSemesterID, key, noteWeek)
                                    draft = ""
                                    edited = false
                                    feedback = "备注已删除"
                                }
                            },
                        ) { Text("删除备注") }
                    }
                    Text(
                        text = if (noteWeek == 0) "适用于这门课的所有周次。" else "仅适用于本周这一次课。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            LeafyContentSurface(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("课前提醒", style = MaterialTheme.typography.titleMedium)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(0, 5, 20, 30).forEach { value ->
                            FilterChip(
                                selected = !selectingCustom && minutes == value,
                                onClick = { minutes = value; selectingCustom = false },
                                enabled = !saving,
                                label = { Text(if (value == 0) "关闭" else "$value 分钟") },
                            )
                        }
                        FilterChip(
                            selected = selectingCustom,
                            enabled = !saving,
                            onClick = { selectingCustom = true },
                            label = { Text("自定义") },
                        )
                    }
                    if (selectingCustom) {
                        LeafyTextField(
                            value = custom,
                            onValueChange = { custom = it },
                            label = { Text("提前分钟数（1–180）") },
                            singleLine = true,
                            isError = custom.toIntOrNull() !in 1..180,
                            modifier = Modifier.fillMaxWidth().bringIntoViewRequester(reminderIntoView).onFocusChanged {
                                if (it.isFocused) focusedField = 2 else if (focusedField == 2) focusedField = 0
                            },
                        )
                    }
                    if (course.duration.size > 1 && (selectingCustom || minutes > 0)) {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            course.duration.distinct().sorted().forEach { period ->
                                FilterChip(selected = anchor == period, onClick = { anchor = period }, label = { Text("第 $period 节开始前") })
                            }
                        }
                    }
                    LeafySecondaryButton(
                        enabled = !saving && reminders != null && (!selectingCustom || custom.toIntOrNull() in 1..180),
                        modifier = Modifier.fillMaxWidth(),
                        onClick = {
                            mutate {
                                dao.save(CourseReminderEntity(course.scopeKey, course.sourceSemesterID, key, if (selectingCustom) custom.toInt() else minutes, anchor))
                                dependencies.reminderScheduler.reconcile()
                                permissionProblem = dependencies.reminderScheduler.permissionProblem()
                                feedback = if (!selectingCustom && minutes == 0) "提醒已关闭" else "提醒配置已保存"
                                if ((selectingCustom || minutes > 0) && Build.VERSION.SDK_INT >= 33 && !androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                                    notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                                }
                            }
                        },
                    ) { Text("应用提醒") }
                    if (reminder != null && reminder.minutes > 0 && permissionProblem != null) {
                        LeafyStatusBanner(
                            "提醒未启用 · $permissionProblem",
                            isError = true,
                            actionLabel = "设置",
                            onAction = {
                                val intent = if (Build.VERSION.SDK_INT >= 31 && !context.getSystemService(android.app.AlarmManager::class.java).canScheduleExactAlarms()) {
                                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))
                                } else {
                                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                }
                                context.startActivity(intent)
                            },
                        )
                    }
                    if (reminder != null && reminder.minutes > 0 && permissionProblem == null && schedulingError == null) {
                        Text("提醒已启用", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
                    }
                    Text(
                        text = "提醒只保存在本机，会为这门课尚未开始的周次创建本地通知。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            schedulingError?.let { LeafyStatusBanner(it, isError = true) }
            error?.let { LeafyStatusBanner(it, isError = true, onDismiss = { error = null }) }
            feedback?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary) }
            Spacer(Modifier.height(16.dp))
        }
    }
    pendingScope?.let { target -> LeafyAlertDialog(onDismissRequest = { pendingScope = null }, title = { Text("放弃未保存的更改？") },
        confirmButton = { LeafyTextButton(onClick = { edited = false; noteWeek = target; pendingScope = null }) { Text("放弃更改") } },
        dismissButton = { LeafyTextButton(onClick = { pendingScope = null }) { Text("继续编辑") } }) }
}

@Composable
private fun CourseDetailInfoRow(
    icon: ImageVector,
    label: String,
    value: String,
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (onClick != null) {
                    Modifier.clickable(role = Role.Button, onClick = onClick)
                } else {
                    Modifier
                },
            )
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(18.dp),
        )
        Text(
            text = label,
            modifier = Modifier.width(52.dp).padding(start = 10.dp),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        trailing?.invoke()
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
            } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message ?: "删除失败，请重试" }
        } }) { Text("删除") } }, dismissButton = { LeafyTextButton(onClick = { deleting = null }) { Text("取消") } }) }
}
