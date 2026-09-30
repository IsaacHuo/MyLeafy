package com.myleafy.android.features.campus

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Assessment
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyErrorState
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafyElevation
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing
import kotlinx.coroutines.delay

@Composable
fun GradesScreen(
    onBack: () -> Unit,
    onAnalysis: () -> Unit = {},
    canSync: Boolean = false,
    viewModel: CampusViewModel = academicViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val syncState by viewModel.syncState.collectAsStateWithLifecycle()

    AcademicDetailScaffold(
        title = "成绩查询",
        syncState = syncState,
        canSync = canSync,
        onBack = onBack,
        onRefresh = { viewModel.refresh(AcademicSyncScope.GRADES_AND_RANKINGS) },
        onConsumeSync = viewModel::consumeSyncResult,
    ) { modifier ->
        when (val state = uiState) {
            CampusUiState.Loading -> LoadingAcademicState(modifier)
            is CampusUiState.Error -> LeafyErrorState(
                title = "成绩数据暂不可用",
                message = state.message,
                modifier = modifier,
                // 本地读取失败：重新订阅本地数据流，不发起教务请求。
                action = {
                    LeafyTextButton(onClick = viewModel::retryLoad) { Text("重新加载") }
                },
            )
            is CampusUiState.Loaded -> GradesContent(state, modifier, onAnalysis)
        }
    }
}

@Composable
fun ExamsScreen(
    onBack: () -> Unit,
    canSync: Boolean = false,
    viewModel: CampusViewModel = academicViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val syncState by viewModel.syncState.collectAsStateWithLifecycle()

    AcademicDetailScaffold(
        title = "考试安排",
        syncState = syncState,
        canSync = canSync,
        onBack = onBack,
        onRefresh = { viewModel.refresh(AcademicSyncScope.EXAMS) },
        onConsumeSync = viewModel::consumeSyncResult,
    ) { modifier ->
        when (val state = uiState) {
            CampusUiState.Loading -> LoadingAcademicState(modifier)
            is CampusUiState.Error -> LeafyErrorState(
                title = "考试数据暂不可用",
                message = state.message,
                modifier = modifier,
                action = {
                    LeafyTextButton(onClick = viewModel::retryLoad) { Text("重新加载") }
                },
            )
            is CampusUiState.Loaded -> LazyColumn(
                modifier = modifier,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(LeafySpacing.page),
                verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
            ) {
                item {
                    Text(
                        text = "共 ${state.exams.size} 场考试",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (state.exams.isNotEmpty()) {
                    item { LeafySectionHeader("考试明细") }
                }
                if (state.exams.isEmpty()) {
                    item {
                        LeafyEmptyState(
                            title = "学校暂未返回考试安排",
                            message = "刷新后查看考试时间和地点。",
                            icon = Icons.Outlined.CalendarMonth,
                        )
                    }
                } else {
                    state.exams.groupBy { it.date }.toSortedMap().forEach { (date, exams) ->
                        item(key = "date:$date") { LeafySectionHeader(date) }
                        items(exams.sortedBy { it.start }, key = { it.id }) { ExamRow(it) }
                    }
                }
            }
        }
    }
}

@Composable
internal fun GradesContent(state: CampusUiState.Loaded, modifier: Modifier, onAnalysis: () -> Unit) {
    var collapsed by rememberSaveable { mutableStateOf(emptyList<String>()) }
    val groups = remember(state.grades) { state.grades.groupBy { it.term }.toSortedMap(reverseOrder()) }
    LazyColumn(
        modifier = modifier,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(LeafySpacing.page),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        item(key = "summary") {
            LeafyContentSurface(modifier = Modifier.fillMaxWidth().clickable(onClickLabel = "查看成绩分析详情", onClick = onAnalysis)) {
                Column(Modifier.padding(LeafySpacing.card), verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("成绩分析", style = MaterialTheme.typography.titleMedium)
                        Text("查看分析", color = MaterialTheme.colorScheme.primary)
                    }
                    GradeOverview(state.analytics)
                }
            }
        }
        if (groups.isEmpty()) item {
            LeafyEmptyState(title = "暂无成绩", message = "刷新后查看课程成绩。", icon = Icons.Outlined.Assessment)
        }
        groups.forEach { (term, grades) ->
            item(key = "term:$term") {
                androidx.compose.material3.TextButton(
                    onClick = { collapsed = if (term in collapsed) collapsed - term else collapsed + term },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(term, modifier = Modifier.padding(end = 12.dp), style = MaterialTheme.typography.titleSmall)
                        Text("${grades.size} 门 · ${if (term in collapsed) "展开" else "收起"}")
                    }
                }
            }
            if (term !in collapsed) items(grades, key = { "grade:${it.id}" }) { GradeRow(it) }
        }
    }
}

@Composable
internal fun AcademicMetric(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.primary)
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun AcademicDetailScaffold(
    title: String,
    syncState: CampusSyncState,
    onBack: () -> Unit,
    canSync: Boolean,
    onRefresh: () -> Unit,
    onConsumeSync: () -> Unit,
    content: @Composable (Modifier) -> Unit,
) {
    LeafySecondaryScaffold(
        title = title,
        onBack = onBack,
        actions = {
            if (canSync) LeafyActionIconButton(onClick = onRefresh, enabled = syncState !is CampusSyncState.Syncing) {
                if (syncState is CampusSyncState.Syncing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(LeafyIconSize.standard),
                        strokeWidth = 2.dp,
                    )
                } else {
                    Icon(Icons.Outlined.Refresh, contentDescription = "刷新")
                }
            }
        },
    ) { scaffoldModifier ->
        Column(modifier = scaffoldModifier.fillMaxSize()) {
            if (syncState is CampusSyncState.Success) {
                LeafyStatusBanner(
                    message = syncMessage(syncState).orEmpty(),
                    isError = syncState.warnings.isNotEmpty(),
                    modifier = Modifier.padding(horizontal = LeafySpacing.page, vertical = LeafySpacing.micro),
                    actionLabel = if (syncState.warnings.isNotEmpty()) "重试" else null,
                    onAction = if (syncState.warnings.isNotEmpty()) onRefresh else null,
                    onDismiss = onConsumeSync,
                )
                // 成功提示短暂出现后自动收起。
                LaunchedEffect(syncState) {
                    if (syncState.warnings.isEmpty()) {
                        delay(4_000)
                        onConsumeSync()
                    }
                }
            } else if (syncState is CampusSyncState.Error) {
                // 失败保留在屏幕上，直到用户重试、同步成功或主动关闭。
                LeafyStatusBanner(
                    message = syncMessage(syncState).orEmpty(),
                    isError = true,
                    modifier = Modifier.padding(horizontal = LeafySpacing.page, vertical = LeafySpacing.micro),
                    actionLabel = "重试",
                    onAction = onRefresh,
                    onDismiss = onConsumeSync,
                )
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
    LeafyLoadingState(modifier = modifier)
}

@Composable
internal fun academicViewModel(): CampusViewModel = viewModel(
    factory = appViewModelFactory { container ->
        CampusViewModel(container.academicRepository, SemesterConfig.currentSemesterId)
    },
)
