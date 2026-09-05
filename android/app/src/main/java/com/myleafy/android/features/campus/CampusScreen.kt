package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Class
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.Assessment
import androidx.compose.material.icons.automirrored.outlined.DirectionsRun
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.outlined.LocalHospital
import androidx.compose.material.icons.outlined.RateReview
import androidx.compose.material.icons.outlined.SportsBasketball
import androidx.compose.material.icons.outlined.School
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.navigation.FeatureDestination
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyErrorState
import com.myleafy.android.ui.components.LeafyFeatureCard
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafyAdaptiveTokens
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyElevation
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyStroke
import com.myleafy.android.ui.theme.leafySurfaces
import kotlinx.coroutines.delay

@Composable
fun CampusScreen(
    onGradesClick: () -> Unit = {},
    onExamsClick: () -> Unit = {},
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
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val syncState by viewModel.syncState.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.leafySurfaces.page,
        topBar = {
            LeafyRootTopBar(
                title = "校园",
                actions = {
                    LeafyActionIconButton(
                        onClick = viewModel::refresh,
                        enabled = syncState !is CampusSyncState.Syncing,
                    ) {
                        if (syncState is CampusSyncState.Syncing) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(LeafyIconSize.standard),
                                strokeWidth = LeafyStroke.progress,
                            )
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
                LeafyLoadingState(modifier = Modifier.fillMaxSize().padding(contentPadding))
            }
            is CampusUiState.Error -> {
                LeafyErrorState(
                    title = "校园数据暂不可用",
                    message = state.message,
                    modifier = Modifier.fillMaxSize().padding(contentPadding),
                    action = {
                        LeafyTextButton(onClick = viewModel::refresh) { Text("重试") }
                    },
                )
            }
            is CampusUiState.Loaded -> {
                CampusDashboard(
                    state = state,
                    syncState = syncState,
                    onConsumeSync = viewModel::consumeSyncResult,
                    onGradesClick = onGradesClick,
                    onExamsClick = onExamsClick,
                    onClassroomClick = onClassroomClick,
                    onFeatureClick = onFeatureClick,
                    modifier = Modifier.fillMaxSize().padding(contentPadding),
                )
            }
        }
    }
}

@Composable
internal fun CampusDashboard(
    state: CampusUiState.Loaded,
    syncState: CampusSyncState,
    onConsumeSync: () -> Unit,
    onGradesClick: () -> Unit,
    onExamsClick: () -> Unit,
    onClassroomClick: () -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedDomain by rememberSaveable { androidx.compose.runtime.mutableStateOf(CampusDomain.Teaching) }

    BoxWithConstraints(modifier = modifier) {
        if (maxWidth >= LeafyAdaptiveTokens.twoPaneBreakpoint) {
            Row(
                modifier = Modifier.fillMaxSize().padding(horizontal = LeafySpacing.page),
                horizontalArrangement = Arrangement.spacedBy(LeafySpacing.section),
            ) {
                CampusDomainSidebar(
                    selectedDomain = selectedDomain,
                    onDomainSelected = { selectedDomain = it },
                    modifier = Modifier.width(LeafyAdaptiveTokens.campusSidebarWidth).padding(top = LeafySpacing.card),
                )
                CampusDomainContent(
                    domain = selectedDomain,
                    state = state,
                    syncState = syncState,
                    onConsumeSync = onConsumeSync,
                    onGradesClick = onGradesClick,
                    onExamsClick = onExamsClick,
                    onClassroomClick = onClassroomClick,
                    onFeatureClick = onFeatureClick,
                    modifier = Modifier.weight(1f),
                )
            }
        } else {
            Column(modifier = Modifier.fillMaxSize()) {
                CampusDomainChips(
                    selectedDomain = selectedDomain,
                    onDomainSelected = { selectedDomain = it },
                )
                CampusDomainContent(
                    domain = selectedDomain,
                    state = state,
                    syncState = syncState,
                    onConsumeSync = onConsumeSync,
                    onGradesClick = onGradesClick,
                    onExamsClick = onExamsClick,
                    onClassroomClick = onClassroomClick,
                    onFeatureClick = onFeatureClick,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

private enum class CampusDomain(val label: String, val supportingText: String) {
    Teaching("学校教学", "成绩、考试与学期安排"),
    SelfStudy("自习安排", "查询当前可用的学习地点"),
    Sports("体育相关", "长跑、体测与场馆信息"),
    Medical("医疗事项", "政策、报销指引与本机台账"),
    Ratings("评价相关", "评教、评课与评菜"),
}

@Composable
private fun CampusDomainChips(
    selectedDomain: CampusDomain,
    onDomainSelected: (CampusDomain) -> Unit,
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = LeafySpacing.page, vertical = LeafySpacing.compact),
        horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
    ) {
        items(CampusDomain.entries, key = { it.name }) { domain ->
            FilterChip(
                selected = selectedDomain == domain,
                onClick = { onDomainSelected(domain) },
                label = { Text(domain.label) },
            )
        }
    }
}

@Composable
private fun CampusDomainSidebar(
    selectedDomain: CampusDomain,
    onDomainSelected: (CampusDomain) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
        CampusDomain.entries.forEach { domain ->
            Surface(
                onClick = { onDomainSelected(domain) },
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.large,
                color = if (selectedDomain == domain) {
                    MaterialTheme.colorScheme.secondaryContainer
                } else {
                    MaterialTheme.leafySurfaces.page
                },
            ) {
                Column(modifier = Modifier.padding(LeafySpacing.card)) {
                    Text(domain.label, style = MaterialTheme.typography.titleSmall)
                    Text(
                        domain.supportingText,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun CampusDomainContent(
    domain: CampusDomain,
    state: CampusUiState.Loaded,
    syncState: CampusSyncState,
    onConsumeSync: () -> Unit,
    onGradesClick: () -> Unit,
    onExamsClick: () -> Unit,
    onClassroomClick: () -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.widthIn(max = LeafyComponentSize.contentMaxWidth),
        contentPadding = PaddingValues(
            start = LeafySpacing.page,
            top = LeafySpacing.micro,
            end = LeafySpacing.page,
            bottom = LeafySpacing.spacious,
        ),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        if (domain == CampusDomain.Teaching) {
            val syncMessage = when (syncState) {
                is CampusSyncState.Success -> buildString {
                    append("同步完成")
                    syncState.grades?.let { append("：$it 条成绩") }
                    syncState.rankings?.let { append("，$it 条排名") }
                    syncState.exams?.let { append("，$it 场考试") }
                    if (syncState.warnings.isNotEmpty()) append("；${syncState.warnings.joinToString("；")}")
                }
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
        }

        item { LeafySectionHeader(title = domain.label, supportingText = domain.supportingText) }
        if (domain == CampusDomain.Teaching) {
            item {
                LeafyFeatureCard(
                    title = "成绩与排名",
                    description = "成绩明细、官方 GPA 与班级/专业排名",
                    icon = Icons.Outlined.Assessment,
                    onClick = onGradesClick,
                )
            }
            item {
                LeafyFeatureCard(
                    title = "考试安排",
                    description = "查看学校发布的考试时间与地点",
                    icon = Icons.Outlined.CalendarMonth,
                    onClick = onExamsClick,
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
        }
        if (domain == CampusDomain.SelfStudy) {
            item {
                LeafyFeatureCard(
                    title = "空闲教室",
                    description = "按周次和星期查询可用教室",
                    icon = Icons.Outlined.Class,
                    onClick = onClassroomClick,
                )
            }
        }
        if (domain == CampusDomain.Sports) {
            item {
                LeafyFeatureCard(
                    title = "阳光长跑",
                    description = "本机记录、两周进度和自定义规则",
                    icon = Icons.AutoMirrored.Outlined.DirectionsRun,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_SUNSHINE_RUN) },
                )
            }
            item {
                LeafyFeatureCard(
                    title = "体测记录",
                    description = "按项目记录数值、备注并观察趋势",
                    icon = Icons.Outlined.FitnessCenter,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_FITNESS_TEST) },
                )
            }
            item {
                LeafyFeatureCard(
                    title = "场馆开放",
                    description = "北林静态开放时间、预约、收费与备注",
                    icon = Icons.Outlined.SportsBasketball,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_VENUES) },
                )
            }
        }
        if (domain == CampusDomain.Medical) {
            item {
                LeafyFeatureCard(
                    title = "医疗政策与报销台账",
                    description = "按就诊情景查看材料，并在本机管理报销记录",
                    icon = Icons.Outlined.LocalHospital,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_MEDICAL) },
                )
            }
        }
        if (domain == CampusDomain.Ratings) {
            item {
                LeafyFeatureCard(
                    title = "评教、评课、评菜",
                    description = "需要社区身份与校园评价服务支持",
                    icon = Icons.Outlined.RateReview,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_RATINGS) },
                )
            }
        }
    }
}

@Composable
internal fun GradeRow(grade: GradeEntity) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = LeafyElevation.flat,
    ) {
        Row(
            modifier = Modifier.padding(LeafySpacing.card),
            horizontalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
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
internal fun ExamRow(exam: ExamEntity) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = LeafyElevation.flat,
    ) {
        Column(modifier = Modifier.padding(LeafySpacing.card)) {
            Text(text = exam.name, style = MaterialTheme.typography.titleSmall)
            Spacer(modifier = Modifier.height(LeafySpacing.tiny))
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
