package com.myleafy.android.features.timetable

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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

@Composable
fun TimetableScreen(
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

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(20.dp),
    ) {
        Text(text = "课表", style = MaterialTheme.typography.headlineMedium)
        Spacer(modifier = Modifier.height(12.dp))

        when (val state = uiState) {
            is TimetableUiState.Loading -> {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            }

            is TimetableUiState.Error -> {
                Text(
                    text = state.message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            is TimetableUiState.Loaded -> {
                LaunchedEffect(state) {
                    if (selectedWeek == 0) selectedWeek = state.week
                }
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = "学期 ${state.semesterId} · 第 ${state.week} 周",
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "本地已缓存 ${state.courses.size} 门课程",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                Spacer(modifier = Modifier.height(12.dp))

                Button(
                    onClick = viewModel::refresh,
                    enabled = syncState !is TimetableSyncState.Syncing,
                ) {
                    if (syncState is TimetableSyncState.Syncing) {
                        CircularProgressIndicator(
                            modifier = Modifier.height(18.dp),
                            strokeWidth = 2.dp,
                        )
                    } else {
                        Text("同步课表")
                    }
                }
                SyncStatus(syncState, viewModel::consumeSyncResult)
                Spacer(modifier = Modifier.height(8.dp))

                WeekSelector(
                    week = selectedWeek,
                    totalWeeks = SemesterConfig.supportedWeeks,
                    onWeekSelected = { selectedWeek = it },
                )
                Spacer(modifier = Modifier.height(8.dp))

                if (state.courses.isEmpty()) {
                    Text(
                        text = "暂无课程，点击“同步课表”从教务拉取",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.outline,
                    )
                } else {
                    TimetableGrid(courses = state.courses, week = selectedWeek)
                }
            }
        }
    }
}

@Composable
private fun SyncStatus(syncState: TimetableSyncState, onConsume: () -> Unit) {
    LaunchedEffect(syncState) {
        if (syncState is TimetableSyncState.Success || syncState is TimetableSyncState.Error) {
            onConsume()
        }
    }
    val message = when (syncState) {
        is TimetableSyncState.Success -> "同步成功：${syncState.count} 门课程"
        is TimetableSyncState.Error -> "同步失败：${syncState.message}"
        else -> null
    }
    if (message != null) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = if (syncState is TimetableSyncState.Error) {
                MaterialTheme.colorScheme.error
            } else {
                MaterialTheme.colorScheme.primary
            },
        )
        Spacer(modifier = Modifier.height(8.dp))
    }
}
