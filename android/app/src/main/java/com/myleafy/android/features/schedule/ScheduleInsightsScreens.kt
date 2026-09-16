package com.myleafy.android.features.schedule

import android.content.ClipData
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.automirrored.outlined.Label
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.RestoreFromTrash
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryButton
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.features.timetable.domain.TimetableGridProjection
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafySpacing
import androidx.compose.ui.unit.dp
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Composable
private fun insightsViewModel(): ScheduleInsightsViewModel =
    viewModel(factory = appViewModelFactory { ScheduleInsightsViewModel(it.scheduleRepository) })

// ---------------------------------------------------------------- 标签

@Composable
fun ScheduleTagsScreen(
    onBack: () -> Unit,
    viewModel: ScheduleInsightsViewModel = insightsViewModel(),
) {
    val memos by viewModel.memos.collectAsStateWithLifecycle()
    val tags = remember(memos) { ScheduleMemoTagAggregator.summarize(memos) }
    var selectedTag by rememberSaveable { mutableStateOf<String?>(null) }
    val filtered = remember(memos, selectedTag) {
        val tag = selectedTag ?: return@remember memos
        val key = foldTagKey(tag)
        memos.filter { memo -> ScheduleMemoTagParser.decode(memo.tags).any { foldTagKey(it) == key } }
    }

    LeafySecondaryScaffold(title = "标签", onBack = onBack) { contentModifier ->
        LazyColumn(
            modifier = contentModifier.fillMaxSize(),
            contentPadding = PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            if (selectedTag != null) {
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        FilterChip(
                            selected = true,
                            onClick = { selectedTag = null },
                            label = { Text("#$selectedTag · 全部随记") },
                        )
                    }
                }
                if (filtered.isEmpty()) {
                    item {
                        LeafyEmptyState(
                            title = "没有匹配的随记",
                            message = "该标签下的随记可能已移入回收站。",
                            icon = Icons.AutoMirrored.Outlined.Label,
                        )
                    }
                } else {
                    items(filtered, key = { it.id }) { memo -> InsightMemoRow(memo) }
                }
                return@LazyColumn
            }

            if (tags.isEmpty()) {
                item {
                    LeafyEmptyState(
                        title = "还没有标签",
                        message = "在随记正文中使用 #标签，或在编辑随记时填写标签。",
                        icon = Icons.AutoMirrored.Outlined.Label,
                    )
                }
            } else {
                item {
                    LeafySectionHeader(
                        title = "全部标签",
                        supportingText = "共 ${tags.size} 个标签，点击查看对应随记。",
                    )
                }
                items(tags, key = { it.name }) { tag ->
                    Surface(
                        onClick = { selectedTag = tag.name },
                        modifier = Modifier.fillMaxWidth(),
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.large,
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(LeafySpacing.card),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = "#${tag.name}",
                                style = MaterialTheme.typography.titleSmall,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                text = tag.count.toString(),
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- 统计

@Composable
fun ScheduleStatisticsScreen(
    onBack: () -> Unit,
    viewModel: ScheduleInsightsViewModel = insightsViewModel(),
) {
    val memos by viewModel.memos.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val accent = MaterialTheme.colorScheme.primary.toArgb()
    val today = remember { LocalDate.now(scheduleCampusZone) }
    val years = remember(memos) { ScheduleMemoStatisticsCalculator.availableYears(memos, today) }
    var selectedYear by rememberSaveable { mutableIntStateOf(today.year) }
    val effectiveYear = if (selectedYear in years) selectedYear else (years.lastOrNull() ?: today.year)
    val statistics = remember(memos, effectiveYear) {
        ScheduleMemoStatisticsCalculator.calculate(memos, effectiveYear, today)
    }
    var shareError by remember { mutableStateOf<String?>(null) }
    val shareImage: () -> Unit = {
        runCatching {
            val file = ScheduleStatisticsShareImage.render(context, statistics, accent, today)
            shareFile(context, file, "image/png", "分享记录日迹")
        }.onFailure { shareError = it.message ?: "分享图片生成失败" }
    }

    LeafySecondaryScaffold(
        title = "记录日迹",
        onBack = onBack,
        actions = {
            LeafyActionIconButton(onClick = shareImage, enabled = statistics.memoCount > 0) {
                Icon(Icons.Outlined.Share, contentDescription = "分享记录日迹图片")
            }
        },
    ) { contentModifier ->
        if (statistics.memoCount == 0) {
            Box(modifier = contentModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                LeafyEmptyState(
                    title = "还没有记录日迹",
                    message = "写下第一条随记后，这里会逐渐形成你的记录频率和习惯。",
                    icon = Icons.Outlined.BarChart,
                )
            }
            return@LeafySecondaryScaffold
        }
        LazyColumn(
            modifier = contentModifier.fillMaxSize().widthIn(max = LeafyComponentSize.contentMaxWidth),
            contentPadding = PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            shareError?.let { message ->
                item {
                    LeafyStatusBanner(message = message, isError = true)
                    LaunchedEffect(message) { shareError = null }
                }
            }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                    items(years) { year ->
                        FilterChip(
                            selected = year == effectiveYear,
                            onClick = { selectedYear = year },
                            label = { Text("$year 年") },
                        )
                    }
                }
            }
            item {
                LeafySectionHeader(title = "概览", supportingText = "$effectiveYear 年 · 以本机随记统计")
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
                    InsightMetric("总随记", statistics.memoCount.toString(), Modifier.weight(1f))
                    InsightMetric("记录天数", statistics.recordingDayCount.toString(), Modifier.weight(1f))
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
                    InsightMetric("当前连续", "${statistics.currentStreak} 天", Modifier.weight(1f))
                    InsightMetric("最长连续", "${statistics.longestStreak} 天", Modifier.weight(1f))
                }
            }
            item { AnnualFrequencyCard(statistics) }
            item {
                LeafySectionHeader(
                    title = "近 30 天",
                    supportingText = "${statistics.recent30DayMemoCount} 条 · ${statistics.recent30DayRecordingDayCount} 天有记录",
                )
            }
            item { Recent30Card(statistics) }
            item {
                LeafySectionHeader(
                    title = "记录习惯",
                    supportingText = habitSummary(statistics),
                )
            }
            item { HabitCard(statistics) }
            if (statistics.topTags.isNotEmpty()) {
                item { LeafySectionHeader(title = "常用标签") }
                items(statistics.topTags, key = { it.name }) { tag ->
                    val ratio = tag.count.toFloat() / statistics.topTags.first().count
                    Column(verticalArrangement = Arrangement.spacedBy(LeafySpacing.hairline)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("#${tag.name}", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                            Text(
                                "${tag.count} 条",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        LinearProgressIndicator(
                            progress = { ratio },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
            item { LeafySectionHeader(title = "记录里程碑") }
            item {
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(LeafySpacing.card),
                        verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
                    ) {
                        MilestoneRow("第一次记录", statistics.firstRecordingDate?.format(dateFormatter) ?: "—")
                        MilestoneRow(
                            "记录最多的一天",
                            statistics.peakDate?.let { "${it.format(dateFormatter)} · ${statistics.peakMemoCount} 条" } ?: "—",
                        )
                        MilestoneRow("最长连续记录", "${statistics.longestStreak} 天")
                        MilestoneRow("有记录的月份", "${statistics.recordingMonthCount} 个月")
                    }
                }
            }
            item {
                Text(
                    text = "统计在本机完成，导出图片只包含汇总数字。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun InsightMetric(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(modifier = Modifier.padding(LeafySpacing.card)) {
            Text(value, style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.primary)
            Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun AnnualFrequencyCard(statistics: ScheduleMemoStatistics) {
    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(LeafySpacing.card),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
        ) {
            Text("全年记录频率", style = MaterialTheme.typography.titleSmall)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(LeafySpacing.tiny),
                verticalAlignment = Alignment.Bottom,
            ) {
                val max = statistics.selectedYearMonths.maxOf { it.memoCount }.coerceAtLeast(1)
                statistics.selectedYearMonths.forEach { month ->
                    Column(
                        modifier = Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(96.dp * (month.memoCount.toFloat() / max).coerceAtLeast(if (month.memoCount > 0) 0.06f else 0.02f)),
                        ) {
                            Surface(
                                modifier = Modifier.fillMaxSize(),
                                shape = MaterialTheme.shapes.small,
                                color = if (month.memoCount > 0) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.surfaceVariant
                                },
                            ) {}
                        }
                        Text(
                            month.month.toString(),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Recent30Card(statistics: ScheduleMemoStatistics) {
    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(LeafySpacing.card),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny),
        ) {
            statistics.recent30Days.takeLast(28).chunked(7).forEach { week ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(LeafySpacing.tiny),
                ) {
                    week.forEach { day ->
                        val intensity = when {
                            day.count <= 0 -> 0
                            day.count == 1 -> 1
                            day.count == 2 -> 2
                            day.count == 3 -> 3
                            else -> 4
                        }
                        Surface(
                            modifier = Modifier.weight(1f).height(28.dp),
                            shape = MaterialTheme.shapes.small,
                            color = MaterialTheme.colorScheme.primary.copy(
                                alpha = 0.12f + intensity * 0.22f,
                            ),
                        ) {}
                    }
                }
            }
            val recent = statistics.recent30DayMemoCount
            val previous = statistics.previous30DayMemoCount
            Text(
                text = comparisonText(recent, previous),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun HabitCard(statistics: ScheduleMemoStatistics) {
    val weekdays = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(LeafySpacing.card),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            val maxWeekday = statistics.weekdayDistribution.maxOrNull()?.coerceAtLeast(1) ?: 1
            weekdays.forEachIndexed { index, label ->
                val count = statistics.weekdayDistribution.getOrElse(index) { 0 }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(label, style = MaterialTheme.typography.bodySmall, modifier = Modifier.width(40.dp))
                    LinearProgressIndicator(
                        progress = { count.toFloat() / maxWeekday },
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        count.toString(),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = LeafySpacing.micro),
                    )
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            statistics.timePeriodDistribution.forEach { (period, count) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(period.label, style = MaterialTheme.typography.bodySmall, modifier = Modifier.width(40.dp))
                    Text(
                        "$count 条",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun MilestoneRow(label: String, value: String) {
    Row {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
    }
}

private fun habitSummary(statistics: ScheduleMemoStatistics): String {
    val weekdays = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
    val topWeekdayIndex = statistics.weekdayDistribution.indices.maxByOrNull { statistics.weekdayDistribution[it] }
    val topPeriod = statistics.timePeriodDistribution.maxByOrNull { it.value }?.key
    if (topWeekdayIndex == null || topPeriod == null || statistics.memoCount == 0) {
        return "记录多一些后，这里会显示你的常用时间。"
    }
    return "你最常在${weekdays[topWeekdayIndex]}的${topPeriod.label}记录。"
}

private fun comparisonText(recent: Int, previous: Int): String = when {
    previous == 0 && recent == 0 -> "前 30 天和最近 30 天都没有记录。"
    previous == 0 -> "前 30 天暂无记录，最近 30 天记录 $recent 条。"
    else -> "最近 30 天 $recent 条，前 30 天 $previous 条。"
}

// ---------------------------------------------------------------- 回收站

@Composable
fun ScheduleTrashScreen(
    onBack: () -> Unit,
    viewModel: ScheduleInsightsViewModel = insightsViewModel(),
) {
    val trashed by viewModel.trashed.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    var confirmEmpty by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<ScheduleMemoEntity?>(null) }

    LeafySecondaryScaffold(
        title = "回收站",
        onBack = onBack,
        actions = {
            if (trashed.isNotEmpty()) {
                LeafyTextButton(onClick = { confirmEmpty = true }) { Text("清空") }
            }
        },
    ) { contentModifier ->
        Column(modifier = contentModifier.fillMaxSize()) {
            message?.let { value ->
                LeafyStatusBanner(message = value, isError = true)
                LaunchedEffect(value) { viewModel.consumeMessage() }
            }
            if (trashed.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    LeafyEmptyState(
                        title = "回收站为空",
                        message = "已删除的随记会保留在这里；移入回收站的随记不会自动到期。",
                        icon = Icons.Outlined.DeleteSweep,
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(LeafySpacing.page),
                    verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
                ) {
                    items(trashed, key = { it.id }) { memo ->
                        Surface(
                            modifier = Modifier.fillMaxWidth(),
                            shape = MaterialTheme.shapes.large,
                            color = MaterialTheme.colorScheme.surface,
                        ) {
                            Column(modifier = Modifier.padding(LeafySpacing.card)) {
                                Text(
                                    text = memo.body.ifBlank { if (memo.kind == "audio") "录音随记" else "图片随记" },
                                    style = MaterialTheme.typography.bodyMedium,
                                    maxLines = 3,
                                )
                                Spacer(Modifier.height(LeafySpacing.micro))
                                Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                                    LeafyTextButton(onClick = { viewModel.restore(memo.id) }) {
                                        Icon(Icons.Outlined.RestoreFromTrash, contentDescription = null)
                                        Text("恢复", modifier = Modifier.padding(start = LeafySpacing.tiny))
                                    }
                                    LeafyTextButton(onClick = { pendingDelete = memo }) { Text("彻底删除") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (confirmEmpty) {
        LeafyAlertDialog(
            onDismissRequest = { confirmEmpty = false },
            title = { Text("清空回收站") },
            text = { Text("将彻底删除回收站中的 ${trashed.size} 条随记，且无法恢复。") },
            confirmButton = {
                LeafyTextButton(onClick = {
                    confirmEmpty = false
                    viewModel.emptyTrash()
                }) { Text("清空") }
            },
            dismissButton = { LeafyTextButton(onClick = { confirmEmpty = false }) { Text("取消") } },
        )
    }
    pendingDelete?.let { memo ->
        LeafyAlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("彻底删除") },
            text = { Text("该随记将被永久删除，无法恢复。") },
            confirmButton = {
                LeafyTextButton(onClick = {
                    pendingDelete = null
                    viewModel.deleteForever(memo.id)
                }) { Text("删除") }
            },
            dismissButton = { LeafyTextButton(onClick = { pendingDelete = null }) { Text("取消") } },
        )
    }
}

// ---------------------------------------------------------------- 每日回顾

@Composable
fun ScheduleReviewScreen(
    onBack: () -> Unit,
    viewModel: ScheduleInsightsViewModel = insightsViewModel(),
) {
    val memos by viewModel.memos.collectAsStateWithLifecycle()
    var page by rememberSaveable { mutableIntStateOf(0) }
    val today = remember { LocalDate.now(scheduleCampusZone) }
    val selection = remember(memos, page) {
        ScheduleMemoReviewEngine.select(memos, today, page)
    }

    LeafySecondaryScaffold(title = "每日回顾", onBack = onBack) { contentModifier ->
        LazyColumn(
            modifier = contentModifier.fillMaxSize(),
            contentPadding = PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                LeafyStatusBanner(
                    message = "重逢旧想法：优先回顾历年同日，再从旧随记中稳定选取。",
                    isError = false,
                )
            }
            if (selection.isEmpty()) {
                item {
                    LeafyEmptyState(
                        title = "暂无可回顾的随记",
                        message = "记录更多随记后，这里会按日期回顾旧内容。",
                        icon = Icons.AutoMirrored.Outlined.Notes,
                    )
                }
            } else {
                items(selection, key = { it.id }) { memo -> InsightMemoRow(memo) }
                item {
                    LeafySecondaryButton(
                        onClick = { page += 1 },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("换一组") }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- 导出

@Composable
fun ScheduleExportScreen(
    onBack: () -> Unit,
    viewModel: ScheduleInsightsViewModel = insightsViewModel(),
) {
    val memos by viewModel.memos.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var error by remember { mutableStateOf<String?>(null) }
    val exportText: () -> Unit = {
        runCatching {
            val text = ScheduleMemoTextExporter.export(memos)
            val directory = File(context.cacheDir, "schedule-exports").apply { mkdirs() }
            val formatter = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
            val file = File(directory, "MyLeafy-Memos-${formatter.format(LocalDate.now(scheduleCampusZone))}-${System.currentTimeMillis()}.txt")
            file.writeText(text, Charsets.UTF_8)
            shareFile(context, file, "text/plain", "导出随记")
        }.onFailure { error = it.message ?: "导出失败" }
    }

    LeafySecondaryScaffold(title = "导出随记", onBack = onBack) { contentModifier ->
        LazyColumn(
            modifier = contentModifier.fillMaxSize(),
            contentPadding = PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            error?.let { message ->
                item {
                    LeafyStatusBanner(message = message, isError = true)
                    LaunchedEffect(message) { error = null }
                }
            }
            item {
                Text(
                    text = "仅导出当前身份下未移入回收站的本地随记；导出不会上传或删除原始内容。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item {
                LeafyPrimaryButton(
                    onClick = exportText,
                    enabled = memos.isNotEmpty(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Outlined.FileUpload, contentDescription = null)
                    Text("导出为文本（${memos.size} 条）", modifier = Modifier.padding(start = LeafySpacing.micro))
                }
            }
            item {
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(LeafySpacing.card),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
                    ) {
                        Icon(Icons.Outlined.Image, contentDescription = null, modifier = Modifier.size(LeafySpacing.section))
                        Column(modifier = Modifier.weight(1f)) {
                            Text("图片归档", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "当前 Android 版本随记尚未支持图片与附件，暂无可归档的图片。",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- 共享行

@Composable
private fun InsightMemoRow(memo: ScheduleMemoEntity) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface,
        shape = MaterialTheme.shapes.large,
    ) {
        Column(modifier = Modifier.padding(LeafySpacing.card)) {
            if (!memo.title.isNullOrBlank()) {
                Text(memo.title, style = MaterialTheme.typography.titleSmall)
            }
            Text(
                text = memo.body,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 6,
            )
            val tags = ScheduleMemoTagParser.decode(memo.tags)
            if (tags.isNotEmpty()) {
                Text(
                    text = tags.joinToString("  ") { "#$it" },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            Text(
                text = createdDateTime(memo, TimetableGridProjection.campusZone).format(dateTimeFormatter),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

internal fun shareFile(
    context: android.content.Context,
    file: File,
    mimeType: String,
    chooserTitle: String,
) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    context.startActivity(
        Intent.createChooser(
            Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri(file.name, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            },
            chooserTitle,
        ),
    )
}

private val dateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
private val dateTimeFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
