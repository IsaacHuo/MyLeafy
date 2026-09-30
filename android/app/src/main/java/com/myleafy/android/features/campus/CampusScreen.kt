package com.myleafy.android.features.campus

import android.content.Intent
import android.net.Uri
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
import androidx.compose.material.icons.outlined.Functions
import androidx.compose.material.icons.outlined.LocalHospital
import androidx.compose.material.icons.outlined.RateReview
import androidx.compose.material.icons.outlined.SportsBasketball
import androidx.compose.material.icons.outlined.WorkspacePremium
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.navigation.FeatureDestination
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyErrorState
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.components.LeafyToolRow
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
    campusId: CampusID? = CampusID.bjfu,
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
    val syncState by viewModel.syncState.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.leafySurfaces.page,
        topBar = {
            LeafyRootTopBar(
                title = "校园",
                actions = {
                    if (campusId == CampusID.bjfu) LeafyActionIconButton(
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
        CampusDashboard(
            syncState = syncState,
            campusId = campusId,
            onRetrySync = viewModel::refresh,
            onConsumeSync = viewModel::consumeSyncResult,
            onGradesClick = onGradesClick,
            onExamsClick = onExamsClick,
            onClassroomClick = onClassroomClick,
            onFeatureClick = onFeatureClick,
            modifier = Modifier.fillMaxSize().padding(contentPadding),
        )
    }
}

@Composable
internal fun CampusDashboard(
    syncState: CampusSyncState,
    campusId: CampusID?,
    onRetrySync: () -> Unit,
    onConsumeSync: () -> Unit,
    onGradesClick: () -> Unit,
    onExamsClick: () -> Unit,
    onClassroomClick: () -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    val domains = remember(campusId) { CampusDomain.entries.filter { it.isAvailableFor(campusId) } }
    var selectedDomain by rememberSaveable { androidx.compose.runtime.mutableStateOf(CampusDomain.Teaching) }
    val listStates = CampusDomain.entries.associateWith { androidx.compose.foundation.lazy.rememberLazyListState() }
    LaunchedEffect(domains) {
        if (selectedDomain !in domains) selectedDomain = domains.first()
    }

    BoxWithConstraints(modifier = modifier) {
        if (maxWidth >= LeafyAdaptiveTokens.twoPaneBreakpoint) {
            Row(
                modifier = Modifier.fillMaxSize().padding(horizontal = LeafySpacing.page),
                horizontalArrangement = Arrangement.spacedBy(LeafySpacing.section),
            ) {
                CampusDomainSidebar(
                    domains = domains,
                    selectedDomain = selectedDomain,
                    onDomainSelected = { selectedDomain = it },
                    modifier = Modifier.width(LeafyAdaptiveTokens.campusSidebarWidth).padding(top = LeafySpacing.card),
                )
                CampusDomainContent(
                    domain = selectedDomain,
                    listState = listStates.getValue(selectedDomain),
                    syncState = syncState,
                    campusId = campusId,
                    onRetrySync = onRetrySync,
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
                    domains = domains,
                    selectedDomain = selectedDomain,
                    onDomainSelected = { selectedDomain = it },
                )
                CampusDomainContent(
                    domain = selectedDomain,
                    listState = listStates.getValue(selectedDomain),
                    syncState = syncState,
                    campusId = campusId,
                    onRetrySync = onRetrySync,
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
    Ratings("评价相关", "评教、评课与评菜");

    /** 学校服务按当前身份的适用范围展示。 */
    fun isAvailableFor(campusId: CampusID?): Boolean =
        campusId == CampusID.bjfu || this == Teaching || this == Sports
}

@Composable
private fun CampusDomainChips(
    domains: List<CampusDomain>,
    selectedDomain: CampusDomain,
    onDomainSelected: (CampusDomain) -> Unit,
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = LeafySpacing.page, vertical = LeafySpacing.compact),
        horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
    ) {
        items(domains, key = { it.name }) { domain ->
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
    domains: List<CampusDomain>,
    selectedDomain: CampusDomain,
    onDomainSelected: (CampusDomain) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
        domains.forEach { domain ->
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
    listState: androidx.compose.foundation.lazy.LazyListState,
    syncState: CampusSyncState,
    campusId: CampusID?,
    onRetrySync: () -> Unit,
    onConsumeSync: () -> Unit,
    onGradesClick: () -> Unit,
    onExamsClick: () -> Unit,
    onClassroomClick: () -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (domain == CampusDomain.Medical) {
        MedicalScreen(onBack = {}, embedded = true, modifier = modifier, available = campusId == CampusID.bjfu)
        return
    }
    if (domain == CampusDomain.Ratings) {
        CatalogRatingsScreen(onBack = {}, embedded = true, modifier = modifier, available = campusId == CampusID.bjfu)
        return
    }
    val context = LocalContext.current
    LazyColumn(
        state = listState,
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
            when (syncState) {
                is CampusSyncState.Success -> {
                    val syncMessage = buildString {
                        append("同步完成")
                        syncState.grades?.let { append("：$it 条成绩") }
                        syncState.rankings?.let { append("，$it 条排名") }
                        syncState.exams?.let { append("，$it 场考试") }
                        if (syncState.warnings.isNotEmpty()) append("；${syncState.warnings.joinToString("；")}")
                    }
                    item {
                        LeafyStatusBanner(
                            message = syncMessage, isError = syncState.warnings.isNotEmpty(),
                            actionLabel = if (syncState.warnings.isNotEmpty()) "重试" else null,
                            onAction = if (syncState.warnings.isNotEmpty()) onRetrySync else null,
                            onDismiss = onConsumeSync,
                        )
                        // 成功提示短暂出现后自动收起。
                        LaunchedEffect(syncState) {
                            if (syncState.warnings.isEmpty()) {
                                delay(3_000)
                                onConsumeSync()
                            }
                        }
                    }
                }
                // 失败保留在屏幕上，直到用户重试、同步成功或主动关闭。
                is CampusSyncState.Error -> item {
                    LeafyStatusBanner(
                        message = syncState.message,
                        isError = true,
                        actionLabel = "重试",
                        onAction = onRetrySync,
                        onDismiss = onConsumeSync,
                    )
                }
                CampusSyncState.Idle, CampusSyncState.Syncing -> Unit
            }
        }

        if (domain == CampusDomain.Teaching) {
            item {
                CampusToolRow(
                    title = "成绩查询",
                    description = "查看个人课程成绩",
                    icon = Icons.Outlined.Assessment,
                    onClick = onGradesClick,
                )
            }
            item {
                CampusToolRow(
                    title = "考试安排",
                    description = "查看考试时间和地点",
                    icon = Icons.Outlined.CalendarMonth,
                    onClick = onExamsClick,
                )
            }
            if (campusId == CampusID.bjfu) {
            item {
                CampusToolRow(
                    title = "教学与培养",
                    description = "查看课程体系与应取学分",
                    icon = Icons.Outlined.School,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_TRAINING_PLAN) },
                )
            }
            item {
                CampusToolRow(
                    title = "校历与作息",
                    description = "查看学期校历和作息时间",
                    icon = Icons.Outlined.CalendarMonth,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_CALENDAR) },
                )
            }
            item {
                CampusToolRow(
                    title = "综素测算",
                    description = "估算综素分，整理材料",
                    icon = Icons.Outlined.Functions,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_COMPREHENSIVE) },
                )
            }
            }
            item {
                CampusToolRow(
                    title = "荣誉记录",
                    description = "在本机保存奖状证书等文件",
                    icon = Icons.Outlined.WorkspacePremium,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_HONOR_RECORDS) },
                )
            }
        }
        if (domain == CampusDomain.SelfStudy) {
            item {
                CampusToolRow(
                    title = "空闲教室",
                    description = "按周次和星期查询可用教室",
                    icon = Icons.Outlined.Class,
                    onClick = onClassroomClick,
                )
            }
            // 北林图书馆座位预约只对北林身份展示，通用/免登录入口不出现这条外链。
            if (campusId == CampusID.bjfu) {
                item {
                    CampusToolRow(
                        title = "图书馆座位预约",
                        description = "跳转链接",
                        icon = Icons.AutoMirrored.Outlined.MenuBook,
                        onClick = { openExternalUrl(context, "https://seat.bjfu.edu.cn/jsq-v/#/main/index") },
                    )
                }
            }
        }
        if (domain == CampusDomain.Sports) {
            item {
                CampusToolRow(
                    title = "阳光长跑",
                    description = "自定义目标次数、周期和假期周规则",
                    icon = Icons.AutoMirrored.Outlined.DirectionsRun,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_SUNSHINE_RUN) },
                )
            }
            item {
                CampusToolRow(
                    title = "体测记录",
                    description = "记录体测项目和成绩",
                    icon = Icons.Outlined.FitnessCenter,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_FITNESS_TEST) },
                )
            }
            // 场馆开放条目是北林静态信息，其他身份不展示。
            if (campusId == CampusID.bjfu) {
                item {
                    CampusToolRow(
                        title = "场馆开放",
                        description = "场馆开放时间与预约方式",
                        icon = Icons.Outlined.SportsBasketball,
                        onClick = { onFeatureClick(FeatureDestination.CAMPUS_VENUES) },
                    )
                }
            }
        }

    }
}

@Composable
private fun CampusToolRow(
    title: String,
    description: String,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    com.myleafy.android.ui.components.LeafyFeatureCard(
        title = title,
        description = description,
        icon = icon,
        onClick = onClick,
        trailingContent = {
            Icon(
                androidx.compose.material.icons.Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
                modifier = Modifier.size(LeafyIconSize.compact),
            )
        },
    )
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

/** 打开外部链接（图书馆座位预约等）。链接由系统浏览器或对应应用处理。 */
internal fun openExternalUrl(context: android.content.Context, url: String) {
    runCatching {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}
