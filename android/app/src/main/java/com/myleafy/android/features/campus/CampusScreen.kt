package com.myleafy.android.features.campus

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Class
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.School
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
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
import com.myleafy.android.navigation.FeatureDestination
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyFeatureCard
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import kotlinx.coroutines.delay

@Composable
fun CampusScreen(
    onClassroomClick: () -> Unit = {},
    onFeatureClick: (FeatureDestination) -> Unit = {},
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

    Scaffold(
        modifier = modifier,
        topBar = {
            LeafyRootTopBar(
                title = "校园",
                actions = {
                    IconButton(
                        onClick = viewModel::refresh,
                        enabled = syncState !is CampusSyncState.Syncing,
                    ) {
                        if (syncState is CampusSyncState.Syncing) {
                            CircularProgressIndicator(modifier = Modifier.height(20.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Outlined.CloudSync, contentDescription = "同步成绩与考试")
                        }
                    }
                },
            )
        },
    ) { contentPadding ->
        when (val state = uiState) {
            is CampusUiState.Loading -> {
                Column(
                    modifier = Modifier.fillMaxSize().padding(contentPadding),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator(modifier = Modifier.padding(top = 32.dp))
                }
            }
            is CampusUiState.Error -> {
                Column(modifier = Modifier.fillMaxSize().padding(contentPadding).padding(16.dp)) {
                    LeafyStatusBanner(message = state.message, isError = true)
                }
            }
            is CampusUiState.Loaded -> {
                CampusDashboard(
                    state = state,
                    syncState = syncState,
                    onConsumeSync = viewModel::consumeSyncResult,
                    onClassroomClick = onClassroomClick,
                    onFeatureClick = onFeatureClick,
                    modifier = Modifier.fillMaxSize().padding(contentPadding),
                )
            }
        }
    }
}

@Composable
private fun CampusDashboard(
    state: CampusUiState.Loaded,
    syncState: CampusSyncState,
    onConsumeSync: () -> Unit,
    onClassroomClick: () -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(text = "校园服务", style = MaterialTheme.typography.titleLarge)
                    Text(
                        text = "学校数据仅在用户主动同步后更新；未连接校园网时保留最近一次成功缓存。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        val syncMessage = when (syncState) {
            is CampusSyncState.Success -> "同步成功：${syncState.grades} 条成绩，${syncState.exams} 场考试"
            is CampusSyncState.Error -> "同步失败：${syncState.message}"
            else -> null
        }
        if (syncMessage != null) {
            item {
                LeafyStatusBanner(message = syncMessage, isError = syncState is CampusSyncState.Error)
                LaunchedEffect(syncState) {
                    delay(3_000)
                    onConsumeSync()
                }
            }
        }

        item { LeafySectionHeader(title = "常用工具") }
        item {
            LeafyFeatureCard(
                title = "空闲教室",
                description = "按周次和星期查询可用教室",
                icon = Icons.Outlined.Class,
                onClick = onClassroomClick,
            )
        }
        item {
            LeafyFeatureCard(
                title = "培养方案",
                description = "教学计划与毕业要求",
                icon = Icons.Outlined.School,
                onClick = { onFeatureClick(FeatureDestination.CAMPUS_TRAINING_PLAN) },
            )
        }
        item {
            LeafyFeatureCard(
                title = "校历",
                description = "学期、教学周与重要日期",
                icon = Icons.Outlined.CalendarMonth,
                onClick = { onFeatureClick(FeatureDestination.CAMPUS_CALENDAR) },
            )
        }
        item {
            LeafyFeatureCard(
                title = "学习空间",
                description = "学习资料、项目与专注记录",
                icon = Icons.AutoMirrored.Outlined.MenuBook,
                onClick = { onFeatureClick(FeatureDestination.CAMPUS_LEARNING_SPACE) },
            )
        }

        item {
            LeafySectionHeader(
                title = "成绩",
                supportingText = "${state.terms.size} 个学期 · 当前缓存 ${state.grades.size} 条",
            )
        }
        if (state.grades.isEmpty()) {
            item {
                LeafyEmptyState(
                    title = "暂无成绩缓存",
                    message = "成绩依赖学校教务环境，本轮不要求联网验收。",
                    icon = Icons.Outlined.School,
                )
            }
        } else {
            items(state.grades, key = { it.id }) { grade -> GradeRow(grade) }
        }

        item {
            LeafySectionHeader(
                title = "考试安排",
                supportingText = "当前缓存 ${state.exams.size} 场",
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        if (state.exams.isEmpty()) {
            item {
                LeafyEmptyState(
                    title = "暂无考试安排",
                    message = "同步成功后的真实考试数据会显示在这里。",
                    icon = Icons.Outlined.CalendarMonth,
                )
            }
        } else {
            items(state.exams, key = { it.id }) { exam -> ExamRow(exam) }
        }
    }
}

@Composable
private fun GradeRow(grade: GradeEntity) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(text = grade.courseName, style = MaterialTheme.typography.titleSmall)
                Text(
                    text = "${grade.type} · ${grade.credit} 学分",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(text = grade.score, style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
private fun ExamRow(exam: ExamEntity) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(text = exam.name, style = MaterialTheme.typography.titleSmall)
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "${exam.date} ${exam.start}–${exam.end}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = exam.location,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
