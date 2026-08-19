package com.myleafy.android.features.timetable

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.features.timetable.domain.SemesterConfig

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
                Spacer(modifier = Modifier.height(12.dp))

                if (state.courses.isEmpty()) {
                    Text(
                        text = "暂无课程，点击“同步课表”从教务拉取",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.outline,
                    )
                } else {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(state.courses, key = { it.id }) { course ->
                            CourseRow(course = course)
                        }
                    }
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

@Composable
private fun CourseRow(course: CourseEntity) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(text = course.courseName, style = MaterialTheme.typography.titleSmall)
            Text(
                text = "${course.teacher} · ${course.location} ${course.room} · 第 ${course.duration.joinToString("-")} 节",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
