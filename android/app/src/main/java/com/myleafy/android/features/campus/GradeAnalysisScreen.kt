package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.ui.components.*
import com.myleafy.android.ui.theme.LeafySpacing
import java.util.Locale

internal fun Double?.gradeNumber(): String = this?.let { String.format(Locale.getDefault(), "%.2f", it) } ?: "--"

@Composable
fun GradeAnalysisScreen(onBack: () -> Unit, canSync: Boolean, viewModel: CampusViewModel = academicViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val sync by viewModel.syncState.collectAsStateWithLifecycle()
    AcademicDetailScaffold("成绩分析", sync, onBack, canSync,
        onRefresh = { viewModel.refresh(AcademicSyncScope.RANKINGS) }, onConsumeSync = viewModel::consumeSyncResult) { modifier ->
        when (val loaded = state) {
            CampusUiState.Loading -> LeafyLoadingState(modifier)
            is CampusUiState.Error -> LeafyErrorState(title = "成绩数据暂不可用", message = loaded.message, modifier = modifier,
                action = { LeafyTextButton(onClick = viewModel::retryLoad) { Text("重新加载") } })
            is CampusUiState.Loaded -> GradeAnalysisContent(loaded, modifier, canSync, sync is CampusSyncState.Syncing) {
                viewModel.refresh(AcademicSyncScope.RANKINGS)
            }
        }
    }
}

@Composable
internal fun GradeAnalysisContent(state: CampusUiState.Loaded, modifier: Modifier = Modifier,
    canSync: Boolean = false, syncing: Boolean = false, onRankingsRefresh: () -> Unit = {}) {
    val analysis = state.analytics
    var sort by rememberSaveable { mutableStateOf("学期") }
    val courses = when (sort) { "低分优先" -> analysis.lowScoreFirst; "影响" -> analysis.highImpact; else -> analysis.courses }
    LazyColumn(modifier, contentPadding = PaddingValues(LeafySpacing.page), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            LeafySectionHeader("概览", supportingText = "${analysis.effectiveCourseCount} 门课程 · ${analysis.rawRecordCount} 条成绩")
            GradeOverview(analysis)
            Text("已获学分 ${analysis.passedCredits.gradeNumber()} · 通过率 ${analysis.passRate?.let { "${(it * 100).gradeNumber()}%" } ?: "--"}",
                Modifier.padding(top = 12.dp), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item { LeafySectionHeader("学期趋势") }
        items(analysis.terms.reversed(), key = { "term:${it.name}" }) { term ->
            AnalysisValueRow(term.name, term.average.gradeNumber(), "${term.courses.size} 门 · ${term.credits.gradeNumber()} 学分")
            term.average?.let { AnalysisBar((it / 100).toFloat()) }
        }
        item { LeafySectionHeader("分数分布") }
        items(analysis.distribution, key = { "bucket:${it.range}" }) { bucket ->
            AnalysisValueRow(bucket.range, "${bucket.count} 门", "${bucket.credits.gradeNumber()} 学分")
            AnalysisBar(if (analysis.scoredCourseCount == 0) 0f else bucket.count.toFloat() / analysis.scoredCourseCount)
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("官方排名", style = MaterialTheme.typography.titleMedium)
                if (canSync) TextButton(onClick = onRankingsRefresh, enabled = !syncing) { Text(if (syncing) "刷新中" else "刷新排名") }
            }
            if (state.rankings.isEmpty()) Text("暂无官方排名", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        items(state.rankings, key = { "ranking:${it.id}" }) { ranking ->
            AnalysisValueRow("${ranking.term} · ${ranking.rankingRange}", ranking.totalCount?.let { "${ranking.rank} / $it" } ?: "第 ${ranking.rank} 名", ranking.metricText)
        }
        item { LeafySectionHeader("课程结构") }
        items(analysis.categories, key = { "category:${it.name}" }) { category ->
            AnalysisValueRow(category.name, "${category.credits.gradeNumber()} 学分", "${category.courses.size} 门 · 加权均分 ${category.average.gradeNumber()}")
        }
        item {
            LeafySectionHeader("课程明细", supportingText = "优先查看低分和高学分课程")
            Text("“影响”按课程分数相对本地加权均分的偏离程度乘以学分排序，不是官方 GPA 预测。",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("学期", "低分优先", "影响").forEach { label -> FilterChip(selected = sort == label, onClick = { sort = label }, label = { Text(label) }) }
            }
        }
        items(courses, key = { "course:${it.record.id}" }) { course ->
            AnalysisValueRow(course.record.courseName, course.record.score,
                "${course.record.term} · ${course.credit.gradeNumber()} 学分 · ${if (course.isPassed) "已通过" else "未通过"}" +
                    if (course.attemptCount > 1) " · ${course.attemptCount} 次成绩" else "")
        }
        item {
            LeafySectionHeader("统计口径", supportingText = "GPA 只使用官方值")
            Text("中位数 ${analysis.median.gradeNumber()} · 标准差 ${analysis.standardDeviation.gradeNumber()}", Modifier.padding(vertical = 12.dp))
            Text((if (analysis.officialGpa == null) "当前缓存没有解析到学校官方 GPA，因此 GPA 暂不展示。" else "页面已解析到学校官方 GPA，GPA 展示只使用官方值。") +
                " 其他统计为本地估算：学校课程按课程编号区分，同编号补考或重修优先取已通过且分数最高记录；缺少编号的记录不跨学期合并。文字等级只用于判断是否通过和计算学分，不换算成分数。",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun AnalysisBar(fraction: Float) {
    Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp))
        .background(MaterialTheme.colorScheme.surfaceContainerHighest)) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).fillMaxHeight()
            .clip(RoundedCornerShape(3.dp)).background(MaterialTheme.colorScheme.primary))
    }
}

@Composable
private fun AnalysisValueRow(title: String, value: String, detail: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(value, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
        }
        Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun GradeOverview(analysis: GradeAnalytics) {
    Column(Modifier.fillMaxWidth().padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            GradeMetric("GPA", analysis.officialGpa.gradeNumber(), if (analysis.officialGpa == null) "未获取官方值" else "学校官方", Modifier.weight(1f))
            GradeMetric("加权均分", analysis.displayWeightedAverage.gradeNumber(), analysis.weightedAverageSource, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            GradeMetric("总学分", analysis.totalCredits.gradeNumber(), "有效课程", Modifier.weight(1f))
            GradeMetric("风险课程", analysis.riskCourseCount.toString(), "未通过", Modifier.weight(1f), analysis.riskCourseCount > 0)
        }
    }
}

@Composable
private fun GradeMetric(label: String, value: String, source: String, modifier: Modifier, risk: Boolean = false) {
    Surface(modifier, shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.headlineSmall, color = if (risk) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface)
            Text(source, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
