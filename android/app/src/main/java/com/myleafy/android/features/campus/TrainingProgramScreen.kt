package com.myleafy.android.features.campus

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.School
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.parsers.ParsedTeachingPlanSection
import com.myleafy.android.parsers.ParsedTrainingProgram
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyStroke

@Composable
fun TrainingProgramScreen(
    onBack: () -> Unit,
    viewModel: TrainingProgramViewModel = viewModel(
        factory = appViewModelFactory { container ->
            TrainingProgramViewModel(
                AcademicDocumentRepository(
                    container.schoolNetworkClient,
                    container.academicDocumentDao,
                    container.activeAppScopeStore,
                ),
            )
        },
    ),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    LaunchedEffect(Unit) { viewModel.initialize() }

    LeafySecondaryScaffold(
        title = "教学与培养",
        onBack = onBack,
        actions = {
            LeafyActionIconButton(
                onClick = viewModel::refresh,
                enabled = !state.loading,
            ) {
                if (state.loading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(LeafyIconSize.standard),
                        strokeWidth = LeafyStroke.progress,
                    )
                } else {
                    Icon(Icons.Outlined.CloudSync, contentDescription = "刷新教学与培养")
                }
            }
        },
    ) { contentModifier ->
        Column(modifier = contentModifier.fillMaxSize()) {
            SingleChoiceSegmentedButtonRow(
                modifier = Modifier.fillMaxWidth().padding(horizontal = LeafySpacing.page, vertical = LeafySpacing.compact),
            ) {
                TrainingProgramMode.entries.forEachIndexed { index, mode ->
                    SegmentedButton(
                        selected = state.mode == mode,
                        onClick = { viewModel.setMode(mode) },
                        shape = SegmentedButtonDefaults.itemShape(index, TrainingProgramMode.entries.size),
                        modifier = Modifier.weight(1f),
                        label = { Text(mode.label) },
                    )
                }
            }
            when (val refresh = state.refreshState) {
                is TrainingProgramRefreshState.Success -> {
                    LeafyStatusBanner(message = refresh.message, isError = false)
                    LaunchedEffect(refresh) {
                        kotlinx.coroutines.delay(3_000)
                        viewModel.consumeRefreshState()
                    }
                }
                is TrainingProgramRefreshState.Error -> {
                    // 失败保留在屏幕上，直到用户重试、成功或主动关闭；
                    // 重试沿用同一个刷新范围，不扩大请求。
                    LeafyStatusBanner(
                        message = refresh.message,
                        isError = true,
                        actionLabel = "重试",
                        onAction = viewModel::refresh,
                        onDismiss = viewModel::consumeRefreshState,
                    )
                }
                else -> Unit
            }
            when (state.mode) {
                TrainingProgramMode.TEACHING_PLAN -> TeachingPlanContent(
                    sections = state.teachingPlan,
                    loading = state.loading,
                    onRetry = viewModel::refresh,
                    modifier = Modifier.weight(1f),
                )
                TrainingProgramMode.TRAINING_PROGRAM -> TrainingProgramContent(
                    program = state.trainingProgram,
                    loading = state.loading,
                    onRetry = viewModel::refresh,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun TeachingPlanContent(
    sections: List<ParsedTeachingPlanSection>,
    loading: Boolean,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (sections.isEmpty() && loading) {
        Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }
    if (sections.isEmpty()) {
        Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            LeafyEmptyState(
                title = "还没有教学计划",
                message = "登录学校账号后刷新，即可按学期查看课程体系与应取学分。",
                icon = Icons.Outlined.School,
                action = { LeafyTextButton(onClick = onRetry) { Text("刷新") } },
            )
        }
        return
    }
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(LeafySpacing.page),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        sections.forEach { section ->
            item(key = "term-${section.term}") {
                LeafySectionHeader(title = section.term, supportingText = "${section.courses.size} 门课程")
            }
            items(section.courses, key = { "${section.term}-${it.courseCode}-${it.name}" }) { course ->
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(LeafySpacing.card)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(course.name, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                            Text(course.credit, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                        }
                        val meta = listOf(course.type, course.courseCategory, course.exam)
                            .filter { it.isNotBlank() }
                            .joinToString(" · ")
                        if (meta.isNotBlank()) {
                            Text(meta, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        val detail = listOf(course.unit.takeIf { it.isNotBlank() }, course.duration.takeIf { it.isNotBlank() })
                            .filterNotNull()
                            .joinToString(" · ")
                        if (detail.isNotBlank()) {
                            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun TrainingProgramContent(
    program: ParsedTrainingProgram?,
    loading: Boolean,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (program == null && loading) {
        Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }
    if (program == null) {
        Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            LeafyEmptyState(
                title = "还没有培养方案",
                message = "登录学校账号后刷新，即可查看课程体系、毕业要求原文与表格。",
                icon = Icons.Outlined.School,
                action = { LeafyTextButton(onClick = onRetry) { Text("刷新") } },
            )
        }
        return
    }
    val context = LocalContext.current
    val tableScrolls = program.tables.map { rememberScrollState() }
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(LeafySpacing.page),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        item {
            Text(program.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        }
        if (program.creditRequirements.any { it.credits !in 0.0..500.0 }) {
            item { LeafyStatusBanner("培养方案包含异常学分，请重新获取", isError = true, actionLabel = "刷新", onAction = onRetry) }
        } else if (program.creditRequirements.isNotEmpty()) {
            item { LeafySectionHeader(title = "毕业学分要求") }
            item {
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(LeafySpacing.card), verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                        program.creditRequirements.forEach { requirement ->
                            Row {
                                Text(
                                    requirement.label,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = if (requirement.isTotal) FontWeight.SemiBold else FontWeight.Normal,
                                    modifier = Modifier.weight(1f),
                                )
                                Text(
                                    "${trimNumber(requirement.credits)} 学分",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                    }
                }
            }
        }
        if (program.sections.isNotEmpty()) {
            item { LeafySectionHeader(title = "培养方案正文") }
            items(program.sections, key = { it.title }) { section ->
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(LeafySpacing.card)) {
                        Text(section.title, style = MaterialTheme.typography.titleSmall)
                        if (section.body.isNotBlank()) {
                            Text(section.body, style = MaterialTheme.typography.bodyMedium)
                        }
                        section.links.forEach { link ->
                            LeafyTextButton(onClick = { openExternalUrl(context, link.url) }) { Text(link.title) }
                        }
                    }
                }
            }
        }
        if (program.tables.isNotEmpty()) {
            item { LeafySectionHeader(title = "课程明细", supportingText = "左右滑动查看完整表格") }
            program.tables.forEachIndexed { tableIndex, table ->
                val columns = table.rows.maxOfOrNull { it.size } ?: 0
                val scroll = tableScrolls[tableIndex]
                stickyHeader(key = "table-$tableIndex-header") {
                    TrainingTableRow(table.rows.firstOrNull().orEmpty(), columns, scroll, header = true)
                }
                itemsIndexed(table.rows.drop(1), key = { row, _ -> "table-$tableIndex-row-$row" }) { _, cells ->
                    TrainingTableRow(cells, columns, scroll, header = false)
                }
            }
        }

        item {
            Text(
                "类别学分不可直接相加，毕业要求以学校公布的培养方案为准。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun trimNumber(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()

@Composable
private fun TrainingTableRow(cells: List<String>, columns: Int, scroll: androidx.compose.foundation.ScrollState, header: Boolean) {
    Surface(modifier = Modifier.fillMaxWidth(), color = if (header) MaterialTheme.colorScheme.surfaceContainerHigh else MaterialTheme.colorScheme.surface) {
        Row(Modifier.horizontalScroll(scroll)) {
            repeat(columns) { column ->
                Text(cells.getOrNull(column).orEmpty(), modifier = Modifier.width(144.dp).padding(10.dp),
                    style = if (header) MaterialTheme.typography.labelLarge else MaterialTheme.typography.bodyMedium)
            }
        }
    }
}
