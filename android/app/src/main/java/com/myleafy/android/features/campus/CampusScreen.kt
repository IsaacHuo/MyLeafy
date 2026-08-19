package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.Column
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
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.timetable.domain.SemesterConfig

@Composable
fun CampusScreen(
    viewModel: CampusViewModel = viewModel(
        factory = appViewModelFactory { container ->
            CampusViewModel(
                repository = container.academicRepository,
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
        Text(text = "校园", style = MaterialTheme.typography.headlineMedium)
        Spacer(modifier = Modifier.height(12.dp))

        when (val state = uiState) {
            is CampusUiState.Loading -> {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            }

            is CampusUiState.Error -> {
                Text(
                    text = state.message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            is CampusUiState.Loaded -> {
                Button(
                    onClick = viewModel::refresh,
                    enabled = syncState !is CampusSyncState.Syncing,
                ) {
                    if (syncState is CampusSyncState.Syncing) {
                        CircularProgressIndicator(modifier = Modifier.height(18.dp), strokeWidth = 2.dp)
                    } else {
                        Text("同步成绩与考试")
                    }
                }
                SyncStatus(syncState, viewModel::consumeSyncResult)
                Spacer(modifier = Modifier.height(12.dp))

                LazyColumn {
                    item {
                        Text(
                            text = "成绩",
                            style = MaterialTheme.typography.titleSmall,
                            modifier = Modifier.padding(bottom = 8.dp),
                        )
                    }
                    if (state.grades.isEmpty()) {
                        item {
                            Text(
                                text = "暂无成绩，点击同步从教务拉取",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.outline,
                                modifier = Modifier.padding(bottom = 16.dp),
                            )
                        }
                    }
                    items(state.grades, key = { it.id }) { grade ->
                        GradeRow(grade)
                    }

                    item {
                        Text(
                            text = "考试安排",
                            style = MaterialTheme.typography.titleSmall,
                            modifier = Modifier.padding(top = 16.dp, bottom = 8.dp),
                        )
                    }
                    if (state.exams.isEmpty()) {
                        item {
                            Text(
                                text = "暂无考试安排",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.outline,
                            )
                        }
                    }
                    items(state.exams, key = { it.id }) { exam ->
                        ExamRow(exam)
                    }
                }
            }
        }
    }
}

@Composable
private fun SyncStatus(syncState: CampusSyncState, onConsume: () -> Unit) {
    LaunchedEffect(syncState) {
        if (syncState is CampusSyncState.Success || syncState is CampusSyncState.Error) {
            onConsume()
        }
    }
    val message = when (syncState) {
        is CampusSyncState.Success -> "同步成功：${syncState.grades} 条成绩，${syncState.exams} 场考试"
        is CampusSyncState.Error -> "同步失败：${syncState.message}"
        else -> null
    }
    if (message != null) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = if (syncState is CampusSyncState.Error) {
                MaterialTheme.colorScheme.error
            } else {
                MaterialTheme.colorScheme.primary
            },
        )
        Spacer(modifier = Modifier.height(8.dp))
    }
}

@Composable
private fun GradeRow(grade: GradeEntity) {
    Card(modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(text = grade.courseName, style = MaterialTheme.typography.titleSmall)
            Text(
                text = "成绩 ${grade.score} · 学分 ${grade.credit} · ${grade.type}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ExamRow(exam: ExamEntity) {
    Card(modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(text = exam.name, style = MaterialTheme.typography.titleSmall)
            Text(
                text = "${exam.date} ${exam.start}~${exam.end} · ${exam.location}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
