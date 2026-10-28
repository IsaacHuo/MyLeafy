package com.myleafy.android.features.campus

import androidx.compose.ui.unit.dp

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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Class
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.Assessment
import androidx.compose.material.icons.automirrored.outlined.DirectionsRun
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.outlined.Functions
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.LocalHospital
import androidx.compose.material.icons.automirrored.outlined.EventNote
import androidx.compose.material.icons.outlined.RateReview
import androidx.compose.material.icons.outlined.SportsBasketball
import androidx.compose.material.icons.outlined.WorkspacePremium
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.platform.testTag
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
    onCommunityClick: () -> Unit = {},
    onScheduleClick: () -> Unit = {},
    onFeatureClick: (FeatureDestination) -> Unit = {},
    campusId: CampusID? = CampusID.bjfu,
    canUseCommunity: Boolean = true,
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
        containerColor = androidx.compose.ui.graphics.Color.Transparent,
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
            onCommunityClick = onCommunityClick,
            onScheduleClick = onScheduleClick,
            canUseCommunity = canUseCommunity,
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
    onCommunityClick: () -> Unit = {},
    onScheduleClick: () -> Unit = {},
    canUseCommunity: Boolean = true,
    onFeatureClick: (FeatureDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    val domains = remember(campusId) { CampusDomain.entries.filter { it.isAvailableFor(campusId) } }
    var selectedDomain by rememberSaveable { androidx.compose.runtime.mutableStateOf(CampusDomain.Life) }
    val listStates = CampusDomain.entries.associateWith { androidx.compose.foundation.lazy.rememberLazyListState() }
    LaunchedEffect(domains) {
        if (selectedDomain !in domains) selectedDomain = domains.first()
    }

    BoxWithConstraints(modifier = modifier) {
        if (maxWidth >= LeafyAdaptiveTokens.twoPaneBreakpoint) {
            // 同步入口在根栏，结果提示必须对每个领域都可见；放进「学校教学」会让
            // 其他领域下的失败/警告被完全隐藏。
            Column(
                modifier = Modifier.fillMaxSize().padding(horizontal = LeafySpacing.page),
            ) {
                if (syncState is CampusSyncState.Success || syncState is CampusSyncState.Error) {
                    CampusSyncBanner(
                        syncState = syncState,
                        onRetrySync = onRetrySync,
                        onConsumeSync = onConsumeSync,
                        modifier = Modifier.padding(top = LeafySpacing.micro),
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth().weight(1f),
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
                        campusId = campusId,
                        onGradesClick = onGradesClick,
                        onExamsClick = onExamsClick,
                        onClassroomClick = onClassroomClick,
                        onCommunityClick = onCommunityClick,
                        onScheduleClick = onScheduleClick,
                        canUseCommunity = canUseCommunity,
                        onFeatureClick = onFeatureClick,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        } else {
            CampusAllToolsContent(
                domains = domains,
                syncState = syncState,
                campusId = campusId,
                onRetrySync = onRetrySync,
                onConsumeSync = onConsumeSync,
                onGradesClick = onGradesClick,
                onExamsClick = onExamsClick,
                onClassroomClick = onClassroomClick,
                onCommunityClick = onCommunityClick,
                onScheduleClick = onScheduleClick,
                canUseCommunity = canUseCommunity,
                onFeatureClick = onFeatureClick,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

private enum class CampusDomain(val label: String, val supportingText: String) {
    Life("校园生活", "社区动态、随记与个人日程"),
    Teaching("学校教学", "成绩、考试与学期安排"),
    SelfStudy("自习安排", "查询当前可用的学习地点"),
    Sports("体育相关", "长跑、体测与场馆信息"),
    Medical("医疗事项", "政策、报销指引与本机台账"),
    Ratings("评价相关", "评教、评课与评菜");

    /** 学校服务按当前身份的适用范围展示；校园生活对所有身份都可见。 */
    fun isAvailableFor(campusId: CampusID?): Boolean =
        this == Life || campusId == CampusID.bjfu || this == Teaching || this == Sports
}

private data class CampusToolItem(
    val key: String,
    val title: String,
    val description: String,
    val icon: ImageVector,
    val onClick: () -> Unit,
) {
    val testTag: String get() = "campus-tool-$key"
}

/**
 * 手机端只保留一个纵向入口列表：工具直接可见，不需要先横向选领域再点卡片。
 * 平板继续使用左侧领域栏 + 右侧内容的双栏结构。
 */
@Composable
private fun CampusAllToolsContent(
    domains: List<CampusDomain>,
    syncState: CampusSyncState,
    campusId: CampusID?,
    onRetrySync: () -> Unit,
    onConsumeSync: () -> Unit,
    onGradesClick: () -> Unit,
    onExamsClick: () -> Unit,
    onClassroomClick: () -> Unit,
    onCommunityClick: () -> Unit,
    onScheduleClick: () -> Unit,
    canUseCommunity: Boolean,
    onFeatureClick: (FeatureDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val sections = domains.map { domain ->
        domain to campusToolsFor(
            domain = domain,
            context = context,
            campusId = campusId,
            canUseCommunity = canUseCommunity,
            onGradesClick = onGradesClick,
            onExamsClick = onExamsClick,
            onClassroomClick = onClassroomClick,
            onCommunityClick = onCommunityClick,
            onScheduleClick = onScheduleClick,
            onFeatureClick = onFeatureClick,
        )
    }
    LazyColumn(
        modifier = modifier.widthIn(max = LeafyComponentSize.contentMaxWidth).testTag("campus-all-tools"),
        contentPadding = PaddingValues(
            start = LeafySpacing.page,
            end = LeafySpacing.page,
            top = LeafySpacing.micro,
            bottom = LeafySpacing.spacious,
        ),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
    ) {
        if (syncState is CampusSyncState.Success || syncState is CampusSyncState.Error) {
            item(key = "campus-sync") {
                CampusSyncBanner(
                    syncState = syncState,
                    onRetrySync = onRetrySync,
                    onConsumeSync = onConsumeSync,
                )
            }
        }
        sections.forEach { (domain, tools) ->
            item(key = "campus-section-${domain.name}") {
                CampusSectionHeader(domain)
            }
            items(tools, key = { it.key }) { tool ->
                CampusToolRow(
                    title = tool.title,
                    description = tool.description,
                    icon = tool.icon,
                    onClick = tool.onClick,
                    modifier = Modifier.testTag(tool.testTag),
                )
            }
        }
    }
}

private fun campusToolsFor(
    domain: CampusDomain,
    context: android.content.Context,
    campusId: CampusID?,
    canUseCommunity: Boolean,
    onGradesClick: () -> Unit,
    onExamsClick: () -> Unit,
    onClassroomClick: () -> Unit,
    onCommunityClick: () -> Unit,
    onScheduleClick: () -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
): List<CampusToolItem> = when (domain) {
    CampusDomain.Life -> buildList {
        if (canUseCommunity) {
            add(
                CampusToolItem(
                    key = "community",
                    title = "校园社区",
                    description = "校园动态、问答、互助与二手",
                    icon = Icons.Outlined.Groups,
                    onClick = onCommunityClick,
                ),
            )
        }
        add(
            CampusToolItem(
                key = "schedule",
                title = "日迹记录",
                description = "随记、个人日程、回顾与导出",
                icon = Icons.AutoMirrored.Outlined.EventNote,
                onClick = onScheduleClick,
            ),
        )
    }

    CampusDomain.Teaching -> buildList {
        add(
            CampusToolItem(
                key = "grades",
                title = "成绩查询",
                description = "查看个人课程成绩",
                icon = Icons.Outlined.Assessment,
                onClick = onGradesClick,
            ),
        )
        add(
            CampusToolItem(
                key = "exams",
                title = "考试安排",
                description = "查看考试时间和地点",
                icon = Icons.Outlined.CalendarMonth,
                onClick = onExamsClick,
            ),
        )
        if (campusId == CampusID.bjfu) {
            add(
                CampusToolItem(
                    key = "training",
                    title = "教学与培养",
                    description = "查看课程体系与应取学分",
                    icon = Icons.Outlined.School,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_TRAINING_PLAN) },
                ),
            )
            add(
                CampusToolItem(
                    key = "calendar",
                    title = "校历与作息",
                    description = "查看学期校历和作息时间",
                    icon = Icons.Outlined.CalendarMonth,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_CALENDAR) },
                ),
            )
            add(
                CampusToolItem(
                    key = "comprehensive",
                    title = "综素测算",
                    description = "估算综素分，整理材料",
                    icon = Icons.Outlined.Functions,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_COMPREHENSIVE) },
                ),
            )
        }
        add(
            CampusToolItem(
                key = "honors",
                title = "荣誉记录",
                description = "在本机保存奖状证书等文件",
                icon = Icons.Outlined.WorkspacePremium,
                onClick = { onFeatureClick(FeatureDestination.CAMPUS_HONOR_RECORDS) },
            ),
        )
    }

    CampusDomain.SelfStudy -> buildList {
        add(
            CampusToolItem(
                key = "classroom",
                title = "空闲教室",
                description = "按周次和星期查询可用教室",
                icon = Icons.Outlined.Class,
                onClick = onClassroomClick,
            ),
        )
        if (campusId == CampusID.bjfu) {
            add(
                CampusToolItem(
                    key = "library",
                    title = "图书馆座位预约",
                    description = "跳转链接",
                    icon = Icons.AutoMirrored.Outlined.MenuBook,
                    onClick = { openExternalUrl(context, "https://seat.bjfu.edu.cn/jsq-v/#/main/index") },
                ),
            )
        }
    }

    CampusDomain.Sports -> buildList {
        add(
            CampusToolItem(
                key = "run",
                title = "阳光长跑",
                description = "自定义目标次数、周期和假期周规则",
                icon = Icons.AutoMirrored.Outlined.DirectionsRun,
                onClick = { onFeatureClick(FeatureDestination.CAMPUS_SUNSHINE_RUN) },
            ),
        )
        add(
            CampusToolItem(
                key = "fitness",
                title = "体测记录",
                description = "记录体测项目和成绩",
                icon = Icons.Outlined.FitnessCenter,
                onClick = { onFeatureClick(FeatureDestination.CAMPUS_FITNESS_TEST) },
            ),
        )
        if (campusId == CampusID.bjfu) {
            add(
                CampusToolItem(
                    key = "venues",
                    title = "场馆开放",
                    description = "场馆开放时间与预约方式",
                    icon = Icons.Outlined.SportsBasketball,
                    onClick = { onFeatureClick(FeatureDestination.CAMPUS_VENUES) },
                ),
            )
        }
    }

    CampusDomain.Medical -> listOf(
        CampusToolItem(
            key = "medical",
            title = "医疗事项",
            description = "政策、报销指引与本机台账",
            icon = Icons.Outlined.LocalHospital,
            onClick = { onFeatureClick(FeatureDestination.CAMPUS_MEDICAL) },
        ),
    )

    CampusDomain.Ratings -> listOf(
        CampusToolItem(
            key = "ratings",
            title = "评价相关",
            description = "评教、评课与评菜",
            icon = Icons.Outlined.RateReview,
            onClick = { onFeatureClick(FeatureDestination.CAMPUS_RATINGS) },
        ),
    )
}

@Composable
private fun CampusSectionHeader(domain: CampusDomain) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = LeafySpacing.compact, bottom = LeafySpacing.tiny),
    ) {
        Text(
            text = domain.label,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            text = domain.supportingText,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun CampusSyncBanner(
    syncState: CampusSyncState,
    onRetrySync: () -> Unit,
    onConsumeSync: () -> Unit,
    modifier: Modifier = Modifier,
) {
    when (syncState) {
        is CampusSyncState.Success -> {
            val message = buildString {
                append("同步完成")
                syncState.grades?.let { append("：$it 条成绩") }
                syncState.rankings?.let { append("，$it 条排名") }
                syncState.exams?.let { append("，$it 场考试") }
                if (syncState.warnings.isNotEmpty()) append("；${syncState.warnings.joinToString("；")}")
            }
            LeafyStatusBanner(
                message = message,
                isError = syncState.warnings.isNotEmpty(),
                actionLabel = if (syncState.warnings.isNotEmpty()) "重试" else null,
                onAction = if (syncState.warnings.isNotEmpty()) onRetrySync else null,
                onDismiss = onConsumeSync,
                modifier = modifier,
            )
            LaunchedEffect(syncState) {
                if (syncState.warnings.isEmpty()) {
                    delay(3_000)
                    onConsumeSync()
                }
            }
        }

        is CampusSyncState.Error -> LeafyStatusBanner(
            message = syncState.message,
            isError = true,
            actionLabel = "重试",
            onAction = onRetrySync,
            onDismiss = onConsumeSync,
            modifier = modifier,
        )

        CampusSyncState.Idle, CampusSyncState.Syncing -> Unit
    }
}

@Composable
private fun CampusDomainSidebar(
    domains: List<CampusDomain>,
    selectedDomain: CampusDomain,
    onDomainSelected: (CampusDomain) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .testTag("campus-domain-sidebar"),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
    ) {
        domains.forEach { domain ->
            Surface(
                onClick = { onDomainSelected(domain) },
                modifier = Modifier.fillMaxWidth().testTag("campus-domain-${domain.name}"),
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
private fun CampusLifeContent(
    onCommunityClick: () -> Unit,
    onScheduleClick: () -> Unit,
    canUseCommunity: Boolean,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.widthIn(max = LeafyComponentSize.contentMaxWidth),
        contentPadding = PaddingValues(
            start = LeafySpacing.page,
            end = LeafySpacing.page,
            top = LeafySpacing.micro,
            bottom = LeafySpacing.section,
        ),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        if (canUseCommunity) {
            item {
                CampusToolRow(
                    title = "校园社区",
                    description = "校园动态、问答、互助与二手",
                    icon = Icons.Outlined.Groups,
                    onClick = onCommunityClick,
                    modifier = Modifier.testTag("campus-life-community"),
                )
            }
        }
        item {
            CampusToolRow(
                title = "日迹记录",
                description = "随记、个人日程、回顾与导出",
                icon = Icons.AutoMirrored.Outlined.EventNote,
                onClick = onScheduleClick,
                modifier = Modifier.testTag("campus-life-schedule"),
            )
        }
    }
}

@Composable
private fun CampusDomainContent(
    domain: CampusDomain,
    listState: androidx.compose.foundation.lazy.LazyListState,
    campusId: CampusID?,
    onGradesClick: () -> Unit,
    onExamsClick: () -> Unit,
    onClassroomClick: () -> Unit,
    onCommunityClick: () -> Unit,
    onScheduleClick: () -> Unit,
    canUseCommunity: Boolean,
    onFeatureClick: (FeatureDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (domain == CampusDomain.Life) {
        CampusLifeContent(
            onCommunityClick = onCommunityClick,
            onScheduleClick = onScheduleClick,
            canUseCommunity = canUseCommunity,
            modifier = modifier,
        )
        return
    }
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
        modifier = modifier.widthIn(max = LeafyComponentSize.contentMaxWidth).testTag("campus-content"),
        contentPadding = PaddingValues(
            start = LeafySpacing.page,
            top = LeafySpacing.micro,
            end = LeafySpacing.page,
            bottom = LeafySpacing.spacious,
        ),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
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
    modifier: Modifier = Modifier,
) {
    com.myleafy.android.ui.components.LeafyFeatureCard(
        title = title,
        description = description,
        icon = icon,
        onClick = onClick,
        modifier = modifier,
        trailingContent = {
            Icon(
                androidx.compose.material.icons.Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = com.myleafy.android.ui.theme.LeafyAlpha.mutedIcon),
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
            Text(text = grade.score, style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.widthIn(max = 112.dp),
                color = MaterialTheme.colorScheme.primary)
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
            Text("课程编号：${exam.courseId.ifBlank { "未填写" }}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            val examStart = runCatching { java.time.LocalDateTime.of(java.time.LocalDate.parse(exam.date), java.time.LocalTime.parse(exam.start)) }.getOrNull()
            val examEnd = runCatching { java.time.LocalDateTime.of(java.time.LocalDate.parse(exam.date), java.time.LocalTime.parse(exam.end)) }.getOrNull()
            val now = java.time.LocalDateTime.now(java.time.ZoneId.of("Asia/Shanghai"))
            Text(when { examStart == null || examEnd == null -> "时间待确认"; now < examStart -> "待开始"; now >= examEnd -> "已结束"; else -> "进行中" }, color = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.height(LeafySpacing.tiny))
            Text(
                text = "${exam.date} ${exam.start}–${exam.end}",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = exam.location.ifBlank { "地点待确认" },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** 打开外部链接（图书馆座位预约等）。链接由系统浏览器或对应应用处理。 */
internal fun openExternalUrl(context: android.content.Context, url: String) {
    try {
        require(Uri.parse(url).scheme in listOf("http", "https")) { "链接格式无效" }
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    } catch (failure: Exception) {
        android.util.Log.e("CampusLink", "Unable to open campus reference", failure)
        android.widget.Toast.makeText(context, failure.message ?: "无法打开链接，请检查浏览器", android.widget.Toast.LENGTH_LONG).show()
    }
}
