package com.myleafy.android.features.campus

import android.content.ClipData
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Functions
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.campus.ComprehensiveQualityComponentKind
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
import com.myleafy.android.ui.theme.LeafySpacing
import java.io.File

private data class ComponentDraft(
    val raw: String = "",
    val peer: String = "",
    val official: String = "",
    val materialReady: Boolean = false,
    val note: String = "",
)

@Composable
fun ComprehensiveQualityScreen(
    onBack: () -> Unit,
    available: Boolean,
    viewModel: ComprehensiveQualityViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ComprehensiveQualityViewModel(
                ComprehensiveQualityRepository(
                    container.comprehensiveQualityDao,
                    container.activeAppScopeStore,
                ),
            )
        },
    ),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var collegeName by rememberSaveable { mutableStateOf("园林学院") }
    var academic by rememberSaveable { mutableStateOf("") }
    var officialQuality by rememberSaveable { mutableStateOf("") }
    var officialComposite by rememberSaveable { mutableStateOf("") }
    var note by rememberSaveable { mutableStateOf("") }
    var drafts by remember { mutableStateOf(ComprehensiveQualityComponentKind.entries.associateWith { ComponentDraft() }) }
    var confirmClear by remember { mutableStateOf(false) }

    val loadedRecord = uiState.record
    LaunchedEffect(loadedRecord?.updatedAt) {
        val record = loadedRecord ?: return@LaunchedEffect
        collegeName = record.collegeName
        academic = record.academicStandardScore?.toPlainString().orEmpty()
        officialQuality = record.officialQualityScore?.toPlainString().orEmpty()
        officialComposite = record.officialCompositeScore?.toPlainString().orEmpty()
        note = record.note
        drafts = ComprehensiveQualityComponentKind.entries.associateWith { kind ->
            val stored = uiState.components.firstOrNull { it.kind == kind.name }
            ComponentDraft(
                raw = stored?.rawScore?.toPlainString().orEmpty(),
                peer = stored?.peerMaxScore?.toPlainString().orEmpty(),
                official = stored?.officialStandardScore?.toPlainString().orEmpty(),
                materialReady = stored?.materialReady ?: false,
                note = stored?.note.orEmpty(),
            )
        }
    }

    val rule = remember(collegeName) { ComprehensiveQualityRuleCatalog.ruleFor(collegeName) }
    val inputs = remember(drafts) {
        ComprehensiveQualityComponentKind.entries.map { kind ->
            val draft = drafts.getValue(kind)
            ComprehensiveQualityComponentInput(
                kind = kind,
                rawScore = draft.raw.toDoubleOrNull(),
                peerMaxScore = draft.peer.toDoubleOrNull(),
                officialStandardScore = draft.official.toDoubleOrNull(),
            )
        }
    }
    val result = remember(rule, inputs, academic) {
        ComprehensiveQualityCalculator.calculate(rule, academic.toDoubleOrNull(), inputs)
    }
    val missing = remember(drafts, academic) { missingItems(drafts, academic) }

    val save: () -> Unit = {
        viewModel.save(
            collegeName = collegeName,
            cohort = "2026届",
            academicStandardScore = academic.toDoubleOrNull(),
            officialQualityScore = officialQuality.toDoubleOrNull(),
            officialCompositeScore = officialComposite.toDoubleOrNull(),
            note = note,
            components = ComprehensiveQualityComponentKind.entries.map { kind ->
                val draft = drafts.getValue(kind)
                StoredComprehensiveComponent(
                    kind = kind.name,
                    rawScore = draft.raw.toDoubleOrNull(),
                    peerMaxScore = draft.peer.toDoubleOrNull(),
                    officialStandardScore = draft.official.toDoubleOrNull(),
                    materialReady = draft.materialReady,
                    note = draft.note,
                )
            },
        )
    }

    val exportCsv: () -> Unit = {
        runCatching {
            val csv = buildCsv(collegeName, rule, result, academic, officialQuality, officialComposite)
            val directory = File(context.cacheDir, "comprehensive-exports").apply { mkdirs() }
            val file = File(directory, "MyLeafy-comprehensive-quality-${System.currentTimeMillis()}.csv")
            file.writeText("\uFEFF" + csv, Charsets.UTF_8)
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            context.startActivity(
                Intent.createChooser(
                    Intent(Intent.ACTION_SEND).apply {
                        type = "text/csv"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        clipData = ClipData.newRawUri(file.name, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    },
                    "分享综素测算",
                ),
            )
        }.onFailure { viewModel.reportError(it.message ?: "导出失败") }
    }

    LeafySecondaryScaffold(
        title = "综素测算",
        onBack = onBack,
        actions = {
            if (available) {
                LeafyActionIconButton(onClick = exportCsv) {
                    Icon(Icons.Outlined.Share, contentDescription = "导出综素测算 CSV")
                }
            }
        },
    ) { contentModifier ->
        if (!available) {
            Box(modifier = contentModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                LeafyEmptyState(
                    title = "综素测算暂不可用",
                    message = "该页面仅在非自定义的北林校园身份下开放。",
                    icon = Icons.Outlined.Functions,
                )
            }
            return@LeafySecondaryScaffold
        }
        LazyColumn(
            modifier = contentModifier.fillMaxSize(),
            contentPadding = PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            message?.let { value ->
                item {
                    LeafyStatusBanner(message = value, isError = true)
                    LaunchedEffect(value) { viewModel.consumeMessage() }
                }
            }
            item {
                Text("选择学院", style = MaterialTheme.typography.titleSmall)
                LazyRow(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                    items(ComprehensiveQualityRuleCatalog.participatingCollegeNames) { name ->
                        FilterChip(
                            selected = name == collegeName,
                            onClick = { collegeName = name },
                            label = { Text(name) },
                        )
                    }
                }
            }
            item {
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(LeafySpacing.card), verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                        Text("规则来源：${rule.status.title}", style = MaterialTheme.typography.titleSmall)
                        Text(rule.sourceTitle, style = MaterialTheme.typography.bodySmall)
                        Text(rule.applicableText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(rule.calculationNote, style = MaterialTheme.typography.bodySmall)
                        Text("更新时间：${rule.updatedAtText}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (rule.sourceUrl.isNotBlank()) {
                            LeafyTextButton(onClick = { openExternalUrl(context, rule.sourceUrl) }) { Text("打开来源") }
                        }
                    }
                }
            }
            item {
                LeafySectionHeader(title = "学业部分", supportingText = "全学程学分积标准分（0–100）")
            }
            item {
                OutlinedTextField(
                    value = academic,
                    onValueChange = { academic = it.filter { ch -> ch.isDigit() || ch == '.' } },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("学分积标准分") },
                    singleLine = true,
                )
            }
            item {
                LeafySectionHeader(
                    title = "综素四项",
                    supportingText = "每项填写官方标准分，或用原始分/专业最高分估算；四项齐全才出最终成绩。",
                )
            }
            items(ComprehensiveQualityComponentKind.entries, key = { it.name }) { kind ->
                val draft = drafts.getValue(kind)
                val componentRule = rule.componentRule(kind)
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(LeafySpacing.card), verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                        Text(
                            "${kind.title} · 权重 ${componentRule?.weightPercent ?: 0.0}%",
                            style = MaterialTheme.typography.titleSmall,
                        )
                        componentRule?.let {
                            Text(it.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                            OutlinedTextField(
                                value = draft.raw,
                                onValueChange = { value -> drafts = drafts.updated(kind, draft.copy(raw = value.filter { it.isDigit() || it == '.' })) },
                                modifier = Modifier.weight(1f),
                                label = { Text("原始分") },
                                singleLine = true,
                            )
                            OutlinedTextField(
                                value = draft.peer,
                                onValueChange = { value -> drafts = drafts.updated(kind, draft.copy(peer = value.filter { it.isDigit() || it == '.' })) },
                                modifier = Modifier.weight(1f),
                                label = { Text("专业最高分") },
                                singleLine = true,
                            )
                        }
                        OutlinedTextField(
                            value = draft.official,
                            onValueChange = { value -> drafts = drafts.updated(kind, draft.copy(official = value.filter { it.isDigit() || it == '.' })) },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("官方标准分（优先）") },
                            singleLine = true,
                        )
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("材料已准备", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                            Switch(
                                checked = draft.materialReady,
                                onCheckedChange = { drafts = drafts.updated(kind, draft.copy(materialReady = it)) },
                            )
                        }
                        val componentResult = result.componentResults.firstOrNull { it.kind == kind }
                        Text(
                            text = when {
                                componentResult?.isComplete == true ->
                                    "折算标准分 ${componentResult.standardScore?.toPlainString()} · 贡献 ${componentResult.contribution?.toPlainString()} 分" +
                                        if (componentResult.isOfficialStandard) "（官方标准分）" else "（本地估算）"
                                else -> "尚未形成可计算的标准分"
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
            item {
                LeafySectionHeader(title = "估算结果")
            }
            item {
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(LeafySpacing.card), verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                        Text(
                            text = if (result.isComplete) "综合成绩 ${result.compositeScore?.toPlainString()}" else "未填满四项，暂不出综合成绩",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            "综素贡献合计：${result.qualityContribution?.toPlainString() ?: "—"} 分",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        if (missing.isNotEmpty()) {
                            Text(
                                "待补齐：" + missing.joinToString("；"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            item {
                LeafySectionHeader(title = "官方结果（可选）", supportingText = "录入学院公示结果，便于对照本地估算。")
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                    OutlinedTextField(
                        value = officialQuality,
                        onValueChange = { officialQuality = it.filter { ch -> ch.isDigit() || ch == '.' } },
                        modifier = Modifier.weight(1f),
                        label = { Text("官方综素分") },
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = officialComposite,
                        onValueChange = { officialComposite = it.filter { ch -> ch.isDigit() || ch == '.' } },
                        modifier = Modifier.weight(1f),
                        label = { Text("官方综合成绩") },
                        singleLine = true,
                    )
                }
            }
            item {
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("备注") },
                    minLines = 2,
                    maxLines = 4,
                )
            }
            item {
                Text(
                    "测算在本机完成，不上传任何材料；结果仅供估算，最终以学院官方公示为准。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item {
                LeafyPrimaryButton(onClick = save, modifier = Modifier.fillMaxWidth()) { Text("保存测算") }
            }
            item {
                LeafySecondaryButton(onClick = { confirmClear = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("清除记录")
                }
            }
        }
    }
    if (confirmClear) {
        LeafyAlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text("清除测算记录") },
            text = { Text("将删除本机保存的综素测算草稿，无法恢复。") },
            confirmButton = {
                LeafyTextButton(onClick = {
                    confirmClear = false
                    viewModel.clear()
                    collegeName = "园林学院"
                    academic = ""
                    officialQuality = ""
                    officialComposite = ""
                    note = ""
                    drafts = ComprehensiveQualityComponentKind.entries.associateWith { ComponentDraft() }
                }) { Text("清除") }
            },
            dismissButton = { LeafyTextButton(onClick = { confirmClear = false }) { Text("取消") } },
        )
    }
}

private fun Map<ComprehensiveQualityComponentKind, ComponentDraft>.updated(
    kind: ComprehensiveQualityComponentKind,
    draft: ComponentDraft,
): Map<ComprehensiveQualityComponentKind, ComponentDraft> = toMutableMap().apply { put(kind, draft) }

private fun missingItems(
    drafts: Map<ComprehensiveQualityComponentKind, ComponentDraft>,
    academic: String,
): List<String> {
    val missing = mutableListOf<String>()
    if (academic.toDoubleOrNull() == null) missing += "学分积标准分"
    ComprehensiveQualityComponentKind.entries.forEach { kind ->
        val draft = drafts.getValue(kind)
        val complete = draft.official.toDoubleOrNull() != null ||
            (draft.raw.toDoubleOrNull() != null && (draft.peer.toDoubleOrNull() ?: 0.0) > 0)
        if (!complete) missing += kind.title
    }
    return missing
}

private fun buildCsv(
    collegeName: String,
    rule: ComprehensiveQualityCollegeRule,
    result: ComprehensiveQualityCalculationResult,
    academic: String,
    officialQuality: String,
    officialComposite: String,
): String {
    fun row(vararg cells: String) = cells.joinToString(",") { cell ->
        "\"" + cell.replace("\"", "\"\"") + "\""
    }
    val lines = mutableListOf<String>()
    lines += row("项目", "值", "备注")
    lines += row("学院", collegeName, rule.status.title)
    lines += row("学分积标准分", academic, "")
    lines += row("综素贡献合计", result.qualityContribution?.toPlainString() ?: "", if (result.isComplete) "本地估算" else "未填满")
    lines += row("综合成绩（本地估算）", result.compositeScore?.toPlainString() ?: "", rule.calculationNote)
    lines += row("官方综素分", officialQuality, "")
    lines += row("官方综合成绩", officialComposite, "")
    result.componentResults.forEach { component ->
        lines += row(
            component.kind.title,
            component.standardScore?.toPlainString() ?: "",
            "贡献 ${component.contribution?.toPlainString() ?: "-"} 分" + if (component.isOfficialStandard) " · 官方标准分" else " · 本地估算",
        )
    }
    return lines.joinToString("\n")
}

private fun Double.toPlainString(): String {
    val rounded = Math.round(this * 100.0) / 100.0
    return if (rounded == rounded.toLong().toDouble()) rounded.toLong().toString() else rounded.toString()
}
