package com.myleafy.android.features.schedule

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
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.timetable.domain.TimetableGridProjection
import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import com.myleafy.android.navigation.FeatureDestination
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafyStatusBanner
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

private enum class ScheduleSection(val label: String) {
    MEMOS("随记"), EVENTS("日程"), REPORTS("推送"),
}

@Composable
fun ScheduleScreen(
    onFeatureClick: (FeatureDestination) -> Unit = {},
    viewModel: ScheduleViewModel = viewModel(
        factory = appViewModelFactory { container -> ScheduleViewModel(container.scheduleRepository) },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val mutationState by viewModel.mutationState.collectAsStateWithLifecycle()
    var selectedSection by rememberSaveable { mutableStateOf(ScheduleSection.MEMOS) }
    var menuExpanded by rememberSaveable { mutableStateOf(false) }
    var memoDraft by remember { mutableStateOf<MemoDraft?>(null) }
    var eventDraft by remember { mutableStateOf<ScheduleEventDraft?>(null) }
    Scaffold(
        modifier = modifier,
        topBar = {
            LeafyRootTopBar(
                title = "日迹",
                actions = {
                    if (selectedSection != ScheduleSection.REPORTS) {
                        IconButton(
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
                        IconButton(onClick = { menuExpanded = true }) {
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
            modifier = Modifier.fillMaxSize().padding(contentPadding).padding(horizontal = 16.dp),
        ) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ScheduleSection.entries.forEach { section ->
                    FilterChip(
                        selected = selectedSection == section,
                        onClick = { selectedSection = section },
                        label = { Text(section.label) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            when (val state = uiState) {
                ScheduleUiState.Loading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
                is ScheduleUiState.Error -> LeafyStatusBanner(message = state.message, isError = true)
                ScheduleUiState.Empty -> ScheduleContent(
                    section = selectedSection,
                    memos = emptyList(),
                    events = emptyList(),
                    onNewMemo = { memoDraft = MemoDraft() },
                    onMemoClick = {},
                    onNewEvent = { eventDraft = defaultScheduleDraft() },
                    onEventClick = {},
                    onFeatureClick = onFeatureClick,
                )
                is ScheduleUiState.Loaded -> ScheduleContent(
                    section = selectedSection,
                    memos = state.memos,
                    events = state.events,
                    onNewMemo = { memoDraft = MemoDraft() },
                    onMemoClick = { memoDraft = it.toDraft() },
                    onNewEvent = { eventDraft = defaultScheduleDraft() },
                    onEventClick = { eventDraft = it.toDraft() },
                    onFeatureClick = onFeatureClick,
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
private fun ScheduleContent(
    section: ScheduleSection,
    memos: List<ScheduleMemoEntity>,
    events: List<ScheduleEventEntity>,
    onNewMemo: () -> Unit,
    onMemoClick: (ScheduleMemoEntity) -> Unit,
    onNewEvent: () -> Unit,
    onEventClick: (ScheduleEventEntity) -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
) {
    when (section) {
        ScheduleSection.MEMOS -> LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Button(onClick = onNewMemo, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text("新建随记", modifier = Modifier.padding(start = 6.dp))
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
            contentPadding = PaddingValues(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Button(onClick = onNewEvent, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text("添加个人日程", modifier = Modifier.padding(start = 6.dp))
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

        ScheduleSection.REPORTS -> LeafyEmptyState(
            title = "日程推送尚未接入",
            message = "系统通知按计划延期；本阶段先保证日程编辑、持久化与课表联动。",
            icon = Icons.Outlined.Notifications,
            action = {
                Button(onClick = { onFeatureClick(FeatureDestination.SCHEDULE_REPORTS) }) {
                    Text("查看功能说明")
                }
            },
        )
    }
}

@Composable
private fun MemoRow(memo: ScheduleMemoEntity, onClick: () -> Unit) {
    Card(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
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
        }
    }
}

@Composable
private fun EventRow(event: ScheduleEventEntity, onClick: () -> Unit) {
    Card(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(text = event.title, style = MaterialTheme.typography.titleSmall)
            Text(
                text = formatEventTime(event) + (event.location?.let { " · $it" } ?: ""),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            event.note?.takeIf(String::isNotBlank)?.let {
                Text(text = it, style = MaterialTheme.typography.bodySmall, maxLines = 2)
            }
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
