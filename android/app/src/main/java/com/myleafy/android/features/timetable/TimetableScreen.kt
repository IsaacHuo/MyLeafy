package com.myleafy.android.features.timetable

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.features.timetable.presentation.TimetableGrid
import com.myleafy.android.features.timetable.presentation.WeekSelector
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafyStatusBanner
import kotlinx.coroutines.delay

@Composable
fun TimetableScreen(
    onShareClick: () -> Unit = {},
    onExportClick: () -> Unit = {},
    onAddScheduleClick: () -> Unit = {},
    viewModel: TimetableViewModel = viewModel(
        factory = appViewModelFactory { container ->
            TimetableViewModel(
                repository = container.timetableRepository,
                semesterId = SemesterConfig.currentSemesterId,
            )
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()
    val syncState by viewModel.syncState.collectAsState()
    var selectedWeek by rememberSaveable { mutableIntStateOf(0) }
    var menuExpanded by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        modifier = modifier,
        topBar = {
            LeafyRootTopBar(
                title = "课表",
                actions = {
                    IconButton(onClick = onAddScheduleClick) {
                        Icon(Icons.Filled.Add, contentDescription = "添加日程")
                    }
                    Box {
                        IconButton(onClick = { menuExpanded = true }) {
                            Icon(Icons.Filled.MoreVert, contentDescription = "课表操作")
                        }
                        DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                            DropdownMenuItem(
                                text = { Text("共享课表") },
                                leadingIcon = { Icon(Icons.Outlined.Share, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    onShareClick()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("导出课表") },
                                leadingIcon = { Icon(Icons.Outlined.FileUpload, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    onExportClick()
                                },
                            )
                        }
                    }
                },
            )
        },
    ) { contentPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding)
                .padding(horizontal = 16.dp),
        ) {
            when (val state = uiState) {
                is TimetableUiState.Loading -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
                }

                is TimetableUiState.Error -> {
                    LeafyStatusBanner(message = state.message, isError = true)
                }

                is TimetableUiState.Loaded -> {
                    LaunchedEffect(state) {
                        if (selectedWeek == 0) selectedWeek = state.week
                    }

                    Card(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(text = "第 ${state.week} 周", style = MaterialTheme.typography.titleLarge)
                                Text(
                                    text = "${state.semesterId} · ${state.courses.size} 门课程已缓存",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            FilledTonalButton(
                                onClick = viewModel::refresh,
                                enabled = syncState !is TimetableSyncState.Syncing,
                            ) {
                                if (syncState is TimetableSyncState.Syncing) {
                                    CircularProgressIndicator(modifier = Modifier.height(18.dp), strokeWidth = 2.dp)
                                } else {
                                    Icon(Icons.Outlined.CloudSync, contentDescription = null)
                                    Text("同步", modifier = Modifier.padding(start = 6.dp))
                                }
                            }
                        }
                    }

                    TimetableSyncBanner(syncState = syncState, onConsume = viewModel::consumeSyncResult)
                    Spacer(modifier = Modifier.height(8.dp))
                    WeekSelector(
                        week = selectedWeek.coerceAtLeast(1),
                        totalWeeks = SemesterConfig.supportedWeeks,
                        onWeekSelected = { selectedWeek = it },
                    )
                    Spacer(modifier = Modifier.height(8.dp))

                    if (state.courses.isEmpty()) {
                        LeafyEmptyState(
                            title = if (state.hasConfirmedSchoolSync) "学校暂未公布课表" else "暂无课表数据",
                            message = if (state.hasConfirmedSchoolSync) {
                                "教务已连接，学校暂未公布或尚未安排 ${state.semesterId} 课表。成绩、排名等其他数据仍可正常使用。"
                            } else {
                                "连接可访问学校教务的网络并完成登录后，可以主动同步课表。"
                            },
                            icon = Icons.Outlined.CloudSync,
                        )
                    } else {
                        Box(modifier = Modifier.weight(1f)) {
                            TimetableGrid(courses = state.courses, week = selectedWeek.coerceAtLeast(1))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TimetableSyncBanner(syncState: TimetableSyncState, onConsume: () -> Unit) {
    val message = when (syncState) {
        is TimetableSyncState.Success -> if (syncState.count == 0) {
            "教务已连接；学校暂未公布或尚未安排本学期课表"
        } else {
            "同步成功：${syncState.count} 门课程"
        }
        is TimetableSyncState.Error -> "同步失败：${syncState.message}"
        else -> null
    }
    if (message != null) {
        LeafyStatusBanner(
            message = message,
            isError = syncState is TimetableSyncState.Error,
            modifier = Modifier.padding(top = 8.dp),
        )
        LaunchedEffect(syncState) {
            delay(3_000)
            onConsume()
        }
    }
}
