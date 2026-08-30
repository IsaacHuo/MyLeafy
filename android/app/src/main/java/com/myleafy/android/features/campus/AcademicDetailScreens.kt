package com.myleafy.android.features.campus

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Assessment
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import kotlinx.coroutines.delay

@Composable
fun GradesScreen(
    onBack: () -> Unit,
    viewModel: CampusViewModel = academicViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val syncState by viewModel.syncState.collectAsStateWithLifecycle()

    AcademicDetailScaffold(
        title = "成绩与排名",
        syncState = syncState,
        onBack = onBack,
        onRefresh = { viewModel.refresh(AcademicSyncScope.GRADES_AND_RANKINGS) },
        onConsumeSync = viewModel::consumeSyncResult,
    ) { modifier ->
        when (val state = uiState) {
            CampusUiState.Loading -> LoadingAcademicState(modifier)
            is CampusUiState.Error -> Column(modifier.padding(16.dp)) {
                LeafyStatusBanner(state.message, isError = true)
            }
            is CampusUiState.Loaded -> GradesContent(state, modifier)
        }
    }
}

@Composable
fun ExamsScreen(
    onBack: () -> Unit,
    viewModel: CampusViewModel = academicViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val syncState by viewModel.syncState.collectAsStateWithLifecycle()

    AcademicDetailScaffold(
        title = "考试安排",
        syncState = syncState,
        onBack = onBack,
        onRefresh = { viewModel.refresh(AcademicSyncScope.EXAMS) },
        onConsumeSync = viewModel::consumeSyncResult,
    ) { modifier ->
        when (val state = uiState) {
            CampusUiState.Loading -> LoadingAcademicState(modifier)
            is CampusUiState.Error -> Column(modifier.padding(16.dp)) {
                LeafyStatusBanner(state.message, isError = true)
            }
            is CampusUiState.Loaded -> LazyColumn(
                modifier = modifier,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                item {
                    Text(
                        text = "${SemesterConfig.currentSemesterId} · ${state.exams.size} 场",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (state.exams.isEmpty()) {
                    item {
                        LeafyEmptyState(
                            title = "学校暂未返回考试安排",
                            message = "已登录时可点右上角刷新；可信空结果不会被当作错误。",
                            icon = Icons.Outlined.CalendarMonth,
                        )
                    }
                } else {
                    items(state.exams, key = { it.id }) { ExamRow(it) }
                }
            }
        }
    }
}

@Composable
private fun GradesContent(state: CampusUiState.Loaded, modifier: Modifier) {
    var selectedTerm by remember(state.terms) { mutableStateOf("全部") }
    val displayedGrades = if (selectedTerm == "全部") state.grades else state.grades.filter { it.term == selectedTerm }
    val overallRankings = state.rankings.filter { it.term == "全部学期" }

    LazyColumn(
        modifier = modifier,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("学校官方概览", style = MaterialTheme.typography.titleMedium)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        AcademicMetric("GPA", state.gradeSummary?.officialGpa?.let { "%.2f".format(it) } ?: "--")
                        AcademicMetric("学分积", state.gradeSummary?.officialCreditPoint?.let { "%.2f".format(it) } ?: "--")
                        AcademicMetric("成绩数", state.grades.size.toString())
                    }
                    Text(
                        "GPA 与排名只展示学校官方值；未解析到时不自行推算。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        item { LeafySectionHeader("官方排名") }
        if (overallRankings.isEmpty()) {
            item {
                LeafyEmptyState(
                    title = "暂无官方排名",
                    message = "学校未返回排名结构时保留最近一次成功缓存。",
                    icon = Icons.Outlined.Assessment,
                )
            }
        } else {
            items(overallRankings, key = { it.id }) { ranking ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(ranking.rankingRange, style = MaterialTheme.typography.titleSmall)
                            Text(
                                ranking.metricText,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(
                            ranking.totalCount?.let { "${ranking.rank} / $it" } ?: "第 ${ranking.rank} 名",
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }

        item { LeafySectionHeader("成绩明细", supportingText = "${state.terms.size} 个学期") }
        item {
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                (listOf("全部") + state.terms).forEach { term ->
                    FilterChip(
                        selected = selectedTerm == term,
                        onClick = { selectedTerm = term },
                        label = { Text(term) },
                    )
                }
            }
        }
        if (displayedGrades.isEmpty()) {
            item {
                LeafyEmptyState(
                    title = "没有成绩记录",
                    message = "登录教务并刷新后显示学校真实成绩。",
                    icon = Icons.Outlined.Assessment,
                )
            }
        } else {
            items(displayedGrades, key = { it.id }) { GradeRow(it) }
        }
    }
}

@Composable
private fun AcademicMetric(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.primary)
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun AcademicDetailScaffold(
    title: String,
    syncState: CampusSyncState,
    onBack: () -> Unit,
    onRefresh: () -> Unit,
    onConsumeSync: () -> Unit,
    content: @Composable (Modifier) -> Unit,
) {
    LeafySecondaryScaffold(
        title = title,
        onBack = onBack,
        actions = {
            IconButton(onClick = onRefresh, enabled = syncState !is CampusSyncState.Syncing) {
                if (syncState is CampusSyncState.Syncing) {
                    CircularProgressIndicator(modifier = Modifier.padding(8.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.Outlined.Refresh, contentDescription = "刷新")
                }
            }
        },
    ) { scaffoldModifier ->
        Column(modifier = scaffoldModifier.fillMaxSize()) {
            val message = syncMessage(syncState)
            if (message != null) {
                LeafyStatusBanner(
                    message = message,
                    isError = syncState is CampusSyncState.Error,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
                LaunchedEffect(syncState) {
                    delay(4_000)
                    onConsumeSync()
                }
            }
            content(Modifier.fillMaxSize())
        }
    }
}

private fun syncMessage(state: CampusSyncState): String? = when (state) {
    CampusSyncState.Idle, CampusSyncState.Syncing -> null
    is CampusSyncState.Error -> state.message
    is CampusSyncState.Success -> buildString {
        append("同步完成")
        state.grades?.let { append("：$it 条成绩") }
        state.rankings?.let { append("，$it 条排名") }
        state.exams?.let { append("，$it 场考试") }
        if (state.warnings.isNotEmpty()) append("；${state.warnings.joinToString("；")}")
    }
}

@Composable
private fun LoadingAcademicState(modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        CircularProgressIndicator(modifier = Modifier.padding(top = 40.dp))
    }
}

@Composable
private fun academicViewModel(): CampusViewModel = viewModel(
    factory = appViewModelFactory { container ->
        CampusViewModel(container.academicRepository, SemesterConfig.currentSemesterId)
    },
)
