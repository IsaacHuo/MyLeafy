package com.myleafy.android.features.schedule

import android.Manifest
import android.os.Build
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Label
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.Switch
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.timetable.domain.TimetableGridProjection
import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import com.myleafy.android.features.schedule.notifications.ScheduleReportMode
import com.myleafy.android.features.schedule.notifications.ScheduleReportSetting
import com.myleafy.android.features.schedule.notifications.ScheduleReportsUiState
import com.myleafy.android.features.schedule.notifications.ScheduleReportsViewModel
import com.myleafy.android.navigation.FeatureDestination
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.leafyMinimumTouchTarget
import com.myleafy.android.ui.theme.LeafyMotion
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

internal enum class ScheduleSection(val label: String) {
    MEMOS("随记"), EVENTS("日程"), REPORTS("推送"),
}

@Composable
fun ScheduleScreen(
    onFeatureClick: (FeatureDestination) -> Unit = {},
    initialSection: String? = null,
    initialEventId: String? = null,
    viewModel: ScheduleViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ScheduleViewModel(
                container.scheduleRepository,
                container.scheduleNotificationScheduler::requestReconcile,
            )
        },
    ),
    reportsViewModel: ScheduleReportsViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ScheduleReportsViewModel(
                container.scheduleNotificationRepository,
                container.scheduleNotificationScheduler,
            )
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val mutationState by viewModel.mutationState.collectAsStateWithLifecycle()
    val reportsState by reportsViewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var selectedSection by rememberSaveable {
        mutableStateOf(if (initialSection == "reports") ScheduleSection.REPORTS else ScheduleSection.EVENTS)
    }
    var menuExpanded by rememberSaveable { mutableStateOf(false) }
    var memoDraft by remember { mutableStateOf<MemoDraft?>(null) }
    var eventDraft by remember { mutableStateOf<ScheduleEventDraft?>(null) }
    var pendingNotificationMode by remember { mutableStateOf<ScheduleReportSetting?>(null) }
    var notificationPermissionDenied by rememberSaveable { mutableStateOf(false) }
    var consumedInitialEvent by rememberSaveable(initialEventId) { mutableStateOf(false) }
    LaunchedEffect(initialEventId, uiState) {
        if (!consumedInitialEvent && !initialEventId.isNullOrBlank()) {
            val event = (uiState as? ScheduleUiState.Loaded)?.events?.firstOrNull { it.id == initialEventId }
            if (event != null) {
                selectedSection = ScheduleSection.EVENTS
                eventDraft = event.toDraft()
                consumedInitialEvent = true
            }
        }
    }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val pending = pendingNotificationMode
        pendingNotificationMode = null
        notificationPermissionDenied = !granted
        if (granted && pending != null) {
            reportsViewModel.setMode(pending.mode, true, pending.hour, pending.minute)
        }
    }
    val enableReport: (ScheduleReportSetting) -> Unit = { setting ->
        val hasPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (hasPermission) {
            reportsViewModel.setMode(setting.mode, true, setting.hour, setting.minute)
        } else {
            pendingNotificationMode = setting
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.leafySurfaces.page,
        topBar = {
            LeafyRootTopBar(
                title = "日迹",
                actions = {
                    if (selectedSection != ScheduleSection.REPORTS) {
                        LeafyActionIconButton(
                            onClick = {
                                if (selectedSection == ScheduleSection.MEMOS) {
                                    memoDraft = MemoDraft()
                                } else {
                                    eventDraft = defaultScheduleDraft()
                                }
                            },
                        ) { Icon(Icons.Filled.Add, contentDescription = "新建${selectedSection.label}") }
                    }
                    Box {
                        LeafyActionIconButton(onClick = { menuExpanded = true }) {
                            Icon(Icons.Filled.MoreVert, contentDescription = "日迹菜单")
                        }
                        DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                            ScheduleMenuItem("标签", Icons.AutoMirrored.Outlined.Label) {
                                menuExpanded = false
                                onFeatureClick(FeatureDestination.SCHEDULE_TAGS)
                            }
                            ScheduleMenuItem("记录日迹", Icons.Outlined.BarChart) {
                                menuExpanded = false
                                onFeatureClick(FeatureDestination.SCHEDULE_STATISTICS)
                            }
                            ScheduleMenuItem("回收站", Icons.Outlined.DeleteSweep) {
                                menuExpanded = false
                                onFeatureClick(FeatureDestination.SCHEDULE_TRASH)
                            }
                        }
                    }
                },
            )
        },
    ) { contentPadding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(contentPadding).padding(horizontal = LeafySpacing.card),
        ) {
            PrimaryTabRow(selectedTabIndex = ScheduleSection.entries.indexOf(selectedSection)) {
                ScheduleSection.entries.forEachIndexed { index, section ->
                    Tab(
                        selected = selectedSection == section,
                        onClick = { selectedSection = section },
                        text = { Text(section.label) },
                        modifier = Modifier.leafyMinimumTouchTarget(),
                    )
                }
            }
            Spacer(modifier = Modifier.height(LeafySpacing.micro))
            when (val state = uiState) {
                ScheduleUiState.Loading -> LeafyLoadingState(message = "正在加载日迹")
                is ScheduleUiState.Error -> LeafyStatusBanner(message = state.message, isError = true)
                ScheduleUiState.Empty -> AnimatedScheduleContent(
                    selectedSection = selectedSection,
                    memos = emptyList(),
                    events = emptyList(),
                    onNewMemo = { memoDraft = MemoDraft() },
                    onMemoClick = {},
                    onNewEvent = { eventDraft = defaultScheduleDraft() },
                    onEventClick = {},
                    onFeatureClick = onFeatureClick,
                    reportsState = reportsState,
                    notificationPermissionDenied = notificationPermissionDenied,
                    onToggleReport = { setting, enabled ->
                        if (enabled) enableReport(setting) else {
                            reportsViewModel.setMode(setting.mode, false, setting.hour, setting.minute)
                        }
                    },
                    onSetEventReminder = reportsViewModel::setEventReminder,
                )
                is ScheduleUiState.Loaded -> AnimatedScheduleContent(
                    selectedSection = selectedSection,
                    memos = state.memos,
                    events = state.events,
                    onNewMemo = { memoDraft = MemoDraft() },
                    onMemoClick = { memoDraft = it.toDraft() },
                    onNewEvent = { eventDraft = defaultScheduleDraft() },
                    onEventClick = { eventDraft = it.toDraft() },
                    onFeatureClick = onFeatureClick,
                    reportsState = reportsState,
                    notificationPermissionDenied = notificationPermissionDenied,
                    onToggleReport = { setting, enabled ->
                        if (enabled) enableReport(setting) else {
                            reportsViewModel.setMode(setting.mode, false, setting.hour, setting.minute)
                        }
                    },
                    onSetEventReminder = reportsViewModel::setEventReminder,
                )
            }
        }
    }

    memoDraft?.let { initial ->
        MemoEditorSheet(
            initial = initial,
            mutationState = mutationState,
            onSave = viewModel::saveMemo,
            onDelete = initial.id?.let { { id -> viewModel.deleteMemo(id) } },
            onConsumeMutation = viewModel::consumeMutation,
            onDismiss = {
                viewModel.consumeMutation()
                memoDraft = null
            },
        )
    }
    eventDraft?.let { initial ->
        ScheduleEventEditorSheet(
            initial = initial,
            mutationState = mutationState,
            onSave = viewModel::saveEvent,
            onDelete = initial.id?.let { { id -> viewModel.deleteEvent(id) } },
            onConsumeMutation = viewModel::consumeMutation,
            onDismiss = {
                viewModel.consumeMutation()
                eventDraft = null
            },
        )
    }
}

@Composable
private fun AnimatedScheduleContent(
    selectedSection: ScheduleSection,
    memos: List<ScheduleMemoEntity>,
    events: List<ScheduleEventEntity>,
    onNewMemo: () -> Unit,
    onMemoClick: (ScheduleMemoEntity) -> Unit,
    onNewEvent: () -> Unit,
    onEventClick: (ScheduleEventEntity) -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
    reportsState: ScheduleReportsUiState,
    notificationPermissionDenied: Boolean,
    onToggleReport: (ScheduleReportSetting, Boolean) -> Unit,
    onSetEventReminder: (String, Boolean, Int) -> Unit,
) {
    AnimatedContent(
        targetState = selectedSection,
        transitionSpec = {
            fadeIn(tween(LeafyMotion.quick, easing = LeafyMotion.easing)) togetherWith
                fadeOut(tween(LeafyMotion.quick, easing = LeafyMotion.easing))
        },
        contentKey = { it },
        label = "schedule-section",
    ) { section ->
        ScheduleContent(
            section = section,
            memos = memos,
            events = events,
            onNewMemo = onNewMemo,
            onMemoClick = onMemoClick,
            onNewEvent = onNewEvent,
            onEventClick = onEventClick,
            onFeatureClick = onFeatureClick,
            reportsState = reportsState,
            notificationPermissionDenied = notificationPermissionDenied,
            onToggleReport = onToggleReport,
            onSetEventReminder = onSetEventReminder,
        )
    }
}

@Composable
private fun ScheduleMenuItem(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(label) },
        leadingIcon = { Icon(icon, contentDescription = null) },
        onClick = onClick,
    )
}

@Composable
internal fun ScheduleContent(
    section: ScheduleSection,
    memos: List<ScheduleMemoEntity>,
    events: List<ScheduleEventEntity>,
    onNewMemo: () -> Unit,
    onMemoClick: (ScheduleMemoEntity) -> Unit,
    onNewEvent: () -> Unit,
    onEventClick: (ScheduleEventEntity) -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
    reportsState: ScheduleReportsUiState,
    notificationPermissionDenied: Boolean,
    onToggleReport: (ScheduleReportSetting, Boolean) -> Unit,
    onSetEventReminder: (String, Boolean, Int) -> Unit,
) {
    when (section) {
        ScheduleSection.MEMOS -> LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                LeafyPrimaryButton(onClick = onNewMemo, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text("新建随记", modifier = Modifier.padding(start = LeafySpacing.micro))
                }
            }
            if (memos.isEmpty()) {
                item {
                    LeafyEmptyState(
                        title = "还没有随记",
                        message = "随记只保存在当前 Android 身份作用域。",
                        icon = Icons.AutoMirrored.Outlined.Notes,
                    )
                }
            } else {
                items(memos, key = { it.id }) { memo ->
                    MemoRow(memo = memo, onClick = { onMemoClick(memo) })
                }
            }
        }

        ScheduleSection.EVENTS -> LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                LeafyPrimaryButton(onClick = onNewEvent, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text("添加个人日程", modifier = Modifier.padding(start = LeafySpacing.micro))
                }
            }
            if (events.isEmpty()) {
                item {
                    LeafyEmptyState(
                        title = "还没有个人日程",
                        message = "从这里或课表空白格添加，保存后两处会立即同步。",
                        icon = Icons.Outlined.CalendarMonth,
                    )
                }
            } else {
                items(events, key = { it.id }) { event ->
                    EventRow(event = event, onClick = { onEventClick(event) })
                }
            }
        }

        ScheduleSection.REPORTS -> ScheduleReportsContent(
            state = reportsState,
            events = events,
            notificationPermissionDenied = notificationPermissionDenied,
            onToggleReport = onToggleReport,
            onSetEventReminder = onSetEventReminder,
        )
    }
}

@Composable
private fun ScheduleReportsContent(
    state: ScheduleReportsUiState,
    events: List<ScheduleEventEntity>,
    notificationPermissionDenied: Boolean,
    onToggleReport: (ScheduleReportSetting, Boolean) -> Unit,
    onSetEventReminder: (String, Boolean, Int) -> Unit,
) {
    val reminders = state.reminders.associateBy { it.eventId }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = LeafySpacing.page),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        item {
            LeafyStatusBanner(
                message = "使用 Android 系统节能调度，省电模式下通知可能稍有延迟。",
                isError = false,
            )
        }
        if (notificationPermissionDenied) {
            item { LeafyStatusBanner(message = "通知权限未授予，推送保持关闭。", isError = true) }
        }
        items(state.settings, key = { it.mode.name }) { setting ->
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.leafySurfaces.page,
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(LeafySpacing.card),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(setting.mode.title, style = MaterialTheme.typography.titleSmall)
                        Text(
                            reportDescription(setting.mode),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            "%02d:%02d".format(setting.hour, setting.minute),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    Switch(
                        checked = setting.enabled,
                        onCheckedChange = { onToggleReport(setting, it) },
                    )
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        }
        item {
            Text("个人日程提醒", style = MaterialTheme.typography.titleLarge)
        }
        if (events.isEmpty()) {
            item {
                LeafyEmptyState(
                    title = "还没有可提醒的日程",
                    message = "在“日程”中添加事项后，可在这里设置提前提醒。",
                    icon = Icons.Outlined.Notifications,
                )
            }
        } else {
            items(events.filter { it.startsAt > System.currentTimeMillis() }, key = { it.id }) { event ->
                val reminder = reminders[event.id]
                Column(
                    modifier = Modifier.fillMaxWidth().padding(vertical = LeafySpacing.tiny),
                    verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(event.title, style = MaterialTheme.typography.titleSmall)
                            Text(
                                Instant.ofEpochMilli(event.startsAt).atZone(TimetableGridProjection.campusZone)
                                    .format(DateTimeFormatter.ofPattern("M月d日 HH:mm")),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = reminder?.enabled == true,
                            onCheckedChange = { onSetEventReminder(event.id, it, reminder?.leadMinutes ?: 30) },
                        )
                    }
                    if (reminder?.enabled == true) {
                        Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.tiny)) {
                            listOf(10 to "10 分", 30 to "30 分", 60 to "1 小时", 1_440 to "1 天").forEach { option ->
                                FilterChip(
                                    selected = reminder.leadMinutes == option.first,
                                    onClick = { onSetEventReminder(event.id, true, option.first) },
                                    label = { Text(option.second) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun reportDescription(mode: ScheduleReportMode): String = when (mode) {
    ScheduleReportMode.MORNING -> "每天汇总今天的课程、考试和个人日程"
    ScheduleReportMode.EVENING -> "每天汇总明天的课程、考试和个人日程"
    ScheduleReportMode.EXAM -> "在考试前 7、3、1 天提醒"
}

@Composable
private fun MemoRow(memo: ScheduleMemoEntity, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.leafySurfaces.page,
    ) {
        Column(modifier = Modifier.padding(LeafySpacing.card)) {
            Text(text = memo.title ?: memo.body, style = MaterialTheme.typography.titleSmall)
            if (memo.title != null && memo.body.isNotBlank()) {
                Text(
                    text = memo.body,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 3,
                )
            }
            if (memo.tags.isNotBlank()) {
                Text(
                    text = memo.tags.lines().joinToString(" · "),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            Spacer(modifier = Modifier.height(LeafySpacing.compact))
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        }
    }
}

@Composable
private fun EventRow(event: ScheduleEventEntity, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.leafySurfaces.page,
    ) {
        Column(modifier = Modifier.padding(LeafySpacing.card)) {
            Text(text = event.title, style = MaterialTheme.typography.titleSmall)
            Text(
                text = formatEventTime(event) + (event.location?.let { " · $it" } ?: ""),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            event.note?.takeIf(String::isNotBlank)?.let {
                Text(text = it, style = MaterialTheme.typography.bodySmall, maxLines = 2)
            }
            Spacer(modifier = Modifier.height(LeafySpacing.compact))
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        }
    }
}

private fun ScheduleMemoEntity.toDraft() = MemoDraft(
    id = id,
    title = title.orEmpty(),
    body = body,
    tags = tags.lines().filter(String::isNotBlank),
)

private fun ScheduleEventEntity.toDraft(): ScheduleEventDraft {
    val start = Instant.ofEpochMilli(startsAt).atZone(TimetableGridProjection.campusZone)
    val end = endsAt?.takeIf { it > startsAt }
        ?.let { Instant.ofEpochMilli(it).atZone(TimetableGridProjection.campusZone) }
        ?: start.plusMinutes(45)
    return ScheduleEventDraft(
        id = id,
        title = title,
        date = start.toLocalDate(),
        startsAt = start.toLocalTime(),
        endsAt = end.toLocalTime(),
        location = location.orEmpty(),
        note = note.orEmpty(),
    )
}

private fun defaultScheduleDraft(): ScheduleEventDraft {
    val now = ZonedDateTime.now(TimetableGridProjection.campusZone)
    val slot = TimetablePeriodSchedule.periodForFocus(now.hour * 60 + now.minute)
        ?: TimetablePeriodSchedule.slots.first()
    return ScheduleEventDraft(
        title = "",
        date = now.toLocalDate(),
        startsAt = LocalTime.of(slot.startHour, slot.startMinute),
        endsAt = LocalTime.of(slot.endHour, slot.endMinute),
        location = "",
        note = "",
    )
}

private val eventFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("M月d日 HH:mm")

private fun formatEventTime(event: ScheduleEventEntity): String {
    val start = Instant.ofEpochMilli(event.startsAt).atZone(TimetableGridProjection.campusZone)
    val end = event.endsAt?.let { Instant.ofEpochMilli(it).atZone(TimetableGridProjection.campusZone) }
    return if (end == null) {
        start.format(eventFormatter)
    } else {
        "${start.format(eventFormatter)}–${end.format(DateTimeFormatter.ofPattern("HH:mm"))}"
    }
}
