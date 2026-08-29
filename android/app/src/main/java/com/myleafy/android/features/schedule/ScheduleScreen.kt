package com.myleafy.android.features.schedule

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.filled.Delete
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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.navigation.FeatureDestination
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafyStatusBanner
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private enum class ScheduleSection(val label: String) {
    MEMOS("随记"),
    EVENTS("日程"),
    REPORTS("推送"),
}

@Composable
fun ScheduleScreen(
    onFeatureClick: (FeatureDestination) -> Unit = {},
    viewModel: ScheduleViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ScheduleViewModel(repository = container.scheduleRepository)
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()
    var memoInput by remember { mutableStateOf("") }
    var selectedSection by rememberSaveable { mutableStateOf(ScheduleSection.MEMOS) }
    var menuExpanded by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        modifier = modifier,
        topBar = {
            LeafyRootTopBar(
                title = "日迹",
                actions = {
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
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
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
                is ScheduleUiState.Loading -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
                }
                is ScheduleUiState.Error -> {
                    LeafyStatusBanner(message = state.message, isError = true)
                }
                is ScheduleUiState.Empty -> {
                    ScheduleContent(
                        section = selectedSection,
                        memos = emptyList(),
                        events = emptyList(),
                        memoInput = memoInput,
                        onMemoInputChange = { memoInput = it },
                        onAddMemo = {
                            viewModel.addMemo(memoInput)
                            memoInput = ""
                        },
                        onDeleteMemo = viewModel::deleteMemo,
                        onDeleteEvent = viewModel::deleteEvent,
                        onFeatureClick = onFeatureClick,
                    )
                }
                is ScheduleUiState.Loaded -> {
                    ScheduleContent(
                        section = selectedSection,
                        memos = state.memos,
                        events = state.events,
                        memoInput = memoInput,
                        onMemoInputChange = { memoInput = it },
                        onAddMemo = {
                            viewModel.addMemo(memoInput)
                            memoInput = ""
                        },
                        onDeleteMemo = viewModel::deleteMemo,
                        onDeleteEvent = viewModel::deleteEvent,
                        onFeatureClick = onFeatureClick,
                    )
                }
            }
        }
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
    memoInput: String,
    onMemoInputChange: (String) -> Unit,
    onAddMemo: () -> Unit,
    onDeleteMemo: (String) -> Unit,
    onDeleteEvent: (String) -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
) {
    when (section) {
        ScheduleSection.MEMOS -> LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(14.dp)) {
                        OutlinedTextField(
                            value = memoInput,
                            onValueChange = onMemoInputChange,
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text("写一条随记…") },
                            minLines = 2,
                            maxLines = 5,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Button(onClick = onAddMemo, enabled = memoInput.isNotBlank()) {
                            Text("保存随记")
                        }
                    }
                }
            }
            if (memos.isEmpty()) {
                item {
                    LeafyEmptyState(
                        title = "还没有随记",
                        message = "随记只保存在当前设备。先写下一条想法或待办吧。",
                        icon = Icons.AutoMirrored.Outlined.Notes,
                    )
                }
            } else {
                items(memos, key = { it.id }) { memo ->
                    MemoRow(memo = memo, onDelete = { onDeleteMemo(memo.id) })
                }
            }
        }

        ScheduleSection.EVENTS -> LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (events.isEmpty()) {
                item {
                    LeafyEmptyState(
                        title = "还没有个人日程",
                        message = "日程编辑器将在下一阶段接入；已有本机日程会在这里显示。",
                        icon = Icons.Outlined.CalendarMonth,
                        action = {
                            Button(onClick = { onFeatureClick(FeatureDestination.TIMETABLE_ADD_SCHEDULE) }) {
                                Text("查看日程入口")
                            }
                        },
                    )
                }
            } else {
                items(events, key = { it.id }) { event ->
                    EventRow(event = event, onDelete = { onDeleteEvent(event.id) })
                }
            }
        }

        ScheduleSection.REPORTS -> LeafyEmptyState(
            title = "日程推送尚未接入",
            message = "这里将管理考试提醒、重要日期报告与设备通知规则。",
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
private fun MemoRow(memo: ScheduleMemoEntity, onDelete: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 8.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(text = memo.title ?: memo.body, style = MaterialTheme.typography.titleSmall)
                if (memo.title != null) {
                    Text(
                        text = memo.body,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 3,
                    )
                }
            }
            IconButton(onClick = onDelete) {
                Icon(imageVector = Icons.Filled.Delete, contentDescription = "删除随记")
            }
        }
    }
}

@Composable
private fun EventRow(event: ScheduleEventEntity, onDelete: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 8.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(text = event.title, style = MaterialTheme.typography.titleSmall)
                Text(
                    text = formatEpoch(event.startsAt) + (event.location?.let { " · $it" } ?: ""),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onDelete) {
                Icon(imageVector = Icons.Filled.Delete, contentDescription = "删除日程")
            }
        }
    }
}

private val eventFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("M月d日 HH:mm").withZone(ZoneId.systemDefault())

private fun formatEpoch(millis: Long): String = eventFormatter.format(Instant.ofEpochMilli(millis))
