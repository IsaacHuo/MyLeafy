package com.myleafy.android.features.campus

import android.content.ClipData
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.automirrored.outlined.DirectionsRun
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.outlined.LocalHospital
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.SportsBasketball
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.data.local.FitnessTestRecordEntity
import com.myleafy.android.core.data.local.MedicalLedgerEntryEntity
import com.myleafy.android.core.data.local.MedicalLedgerPhotoEntity
import com.myleafy.android.core.data.local.SunshineRunRecordEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.math.ceil

@Composable
fun SunshineRunScreen(
    onBack: () -> Unit,
    viewModel: SportsViewModel = sportsViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var showRules by rememberSaveable { mutableStateOf(false) }
    val today = LocalDate.now()
    val currentWeek = (ChronoUnit.DAYS.between(SemesterConfig.current.semesterStartDate, today) / 7 + 1)
        .toInt().coerceIn(1, SemesterConfig.supportedWeeks)
    val excluded = parseWeekSet(state.settings.excludedWeeks)
    val effectiveWeeks = (1..SemesterConfig.supportedWeeks).filterNot(excluded::contains)
    val effectiveIndex = effectiveWeeks.indexOf(currentWeek)
    val periodWeeks = if (effectiveIndex >= 0) {
        val start = (effectiveIndex / state.settings.weeksPerPeriod) * state.settings.weeksPerPeriod
        effectiveWeeks.drop(start).take(state.settings.weeksPerPeriod)
    } else {
        emptyList()
    }
    val periodStart = periodWeeks.firstOrNull() ?: currentWeek
    val periodEnd = periodWeeks.lastOrNull() ?: currentWeek
    val periodRuns = state.runs.count {
        it.periodStartWeek == periodStart && weekForDate(LocalDate.ofEpochDay(it.dateEpochDay)) !in excluded
    }

    LeafySecondaryScaffold(
        title = "阳光长跑",
        onBack = onBack,
        actions = { TextButton(onClick = { showRules = true }) { Text("规则") } },
    ) { contentModifier ->
        LazyColumn(
            modifier = contentModifier,
            contentPadding = PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                Surface(color = MaterialTheme.leafySurfaces.content, shape = MaterialTheme.shapes.large) {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(LeafySpacing.card),
                        verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
                    ) {
                        Text(
                            if (periodWeeks.isEmpty()) "第 $currentWeek 周为排除周" else "有效周 ${periodWeeks.joinToString("、")}",
                            style = MaterialTheme.typography.titleLarge,
                        )
                        Text(
                            "本周期 $periodRuns / ${state.settings.periodTarget} 次 · 全学期 ${state.runs.size} / ${state.settings.totalTarget} 次",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        LinearProgressIndicator(
                            progress = { (state.runs.size.toFloat() / state.settings.totalTarget).coerceIn(0f, 1f) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Button(
                            onClick = { viewModel.addRun(today, periodStart, periodEnd) },
                            enabled = currentWeek !in excluded,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(Icons.AutoMirrored.Outlined.DirectionsRun, contentDescription = null)
                            Text(if (state.runs.any { it.dateEpochDay == today.toEpochDay() }) "今日已记录" else "记录今天")
                        }
                        if (currentWeek in excluded) {
                            Text("第 $currentWeek 周已排除，不计入周期进度。", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
            item { LeafySectionHeader("跑步记录", supportingText = "同一天只保留一条记录，数据仅保存在当前身份作用域。") }
            if (state.runs.isEmpty()) {
                item { LeafyEmptyState("还没有跑步记录", "完成一次后点击“记录今天”。", icon = Icons.AutoMirrored.Outlined.DirectionsRun) }
            } else {
                items(state.runs, key = { it.id }) { run -> RunRow(run, viewModel::deleteRun) }
            }
        }
    }
    if (showRules) {
        SunshineRulesDialog(
            total = state.settings.totalTarget,
            periodWeeks = state.settings.weeksPerPeriod,
            periodTarget = state.settings.periodTarget,
            excludedWeeks = state.settings.excludedWeeks,
            onDismiss = { showRules = false },
            onSave = { total, weeks, target, excludedWeeks ->
                viewModel.saveRules(total, weeks, target, excludedWeeks)
                showRules = false
            },
        )
    }
}

@Composable
private fun RunRow(record: SunshineRunRecordEntity, onDelete: (SunshineRunRecordEntity) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = LeafySpacing.micro),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(LocalDate.ofEpochDay(record.dateEpochDay).format(DateTimeFormatter.ISO_LOCAL_DATE))
            Text("第 ${record.periodStartWeek}–${record.periodEndWeek} 周周期", style = MaterialTheme.typography.bodySmall)
        }
        LeafyActionIconButton(onClick = { onDelete(record) }) {
            Icon(Icons.Outlined.Delete, contentDescription = "删除跑步记录")
        }
    }
}

@Composable
private fun SunshineRulesDialog(
    total: Int,
    periodWeeks: Int,
    periodTarget: Int,
    excludedWeeks: String,
    onDismiss: () -> Unit,
    onSave: (Int, Int, Int, String) -> Unit,
) {
    var totalText by remember(total) { mutableStateOf(total.toString()) }
    var weeksText by remember(periodWeeks) { mutableStateOf(periodWeeks.toString()) }
    var targetText by remember(periodTarget) { mutableStateOf(periodTarget.toString()) }
    var excludedText by remember(excludedWeeks) { mutableStateOf(excludedWeeks) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("长跑规则") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
                NumberField(totalText, { totalText = it }, "全学期目标次数")
                NumberField(weeksText, { weeksText = it }, "每周期周数")
                NumberField(targetText, { targetText = it }, "每周期目标次数")
                OutlinedTextField(
                    value = excludedText,
                    onValueChange = { excludedText = it },
                    label = { Text("排除周（逗号分隔）") },
                    supportingText = { Text("例如：1,8,20") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                onSave(totalText.toIntOrNull() ?: 34, weeksText.toIntOrNull() ?: 2, targetText.toIntOrNull() ?: 4, excludedText)
            }) { Text("保存") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}

@Composable
fun FitnessTestScreen(onBack: () -> Unit, viewModel: SportsViewModel = sportsViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var editorVisible by rememberSaveable { mutableStateOf(false) }
    var filter by rememberSaveable { mutableStateOf("") }
    val items = state.fitnessTests.filter { filter.isBlank() || it.item == filter }
    LeafySecondaryScaffold(
        title = "体测记录",
        onBack = onBack,
        actions = { LeafyActionIconButton(onClick = { editorVisible = true }) { Icon(Icons.Filled.Add, "新增体测") } },
    ) { contentModifier ->
        LazyColumn(
            modifier = contentModifier,
            contentPadding = PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                    listOf("", "1000 米", "立定跳远", "肺活量").forEach { item ->
                        FilterChip(selected = filter == item, onClick = { filter = item }, label = { Text(item.ifBlank { "全部" }) })
                    }
                }
            }
            if (items.isEmpty()) {
                item { LeafyEmptyState("没有符合条件的记录", "新增体测后可按项目筛选。", icon = Icons.Outlined.FitnessCenter) }
            } else {
                items(items, key = { it.id }) { record -> FitnessRow(record, viewModel::deleteFitness) }
            }
        }
    }
    if (editorVisible) {
        FitnessEditorDialog(
            onDismiss = { editorVisible = false },
            onSave = { date, item, value, unit, note ->
                viewModel.saveFitness(date, item, value, unit, note)
                editorVisible = false
            },
        )
    }
}

@Composable
private fun FitnessRow(record: FitnessTestRecordEntity, onDelete: (FitnessTestRecordEntity) -> Unit) {
    Row(modifier = Modifier.fillMaxWidth().padding(vertical = LeafySpacing.micro), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            Text(record.item, style = MaterialTheme.typography.titleSmall)
            Text("${record.value} ${record.unit} · ${LocalDate.ofEpochDay(record.testedAt)}", style = MaterialTheme.typography.bodySmall)
            if (record.note.isNotBlank()) Text(record.note, style = MaterialTheme.typography.bodySmall)
        }
        LeafyActionIconButton(onClick = { onDelete(record) }) { Icon(Icons.Outlined.Delete, "删除体测记录") }
    }
}

@Composable
private fun FitnessEditorDialog(onDismiss: () -> Unit, onSave: (LocalDate, String, Double, String, String) -> Unit) {
    var date by remember { mutableStateOf(LocalDate.now().toString()) }
    var item by remember { mutableStateOf("1000 米") }
    var value by remember { mutableStateOf("") }
    var unit by remember { mutableStateOf("秒") }
    var note by remember { mutableStateOf("") }
    val valid = runCatching { LocalDate.parse(date) }.isSuccess && item.isNotBlank() && value.toDoubleOrNull() != null && unit.isNotBlank()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("新增体测记录") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
                TextFieldValue(date, { date = it }, "日期（YYYY-MM-DD）")
                TextFieldValue(item, { item = it }, "项目")
                TextFieldValue(value, { value = it }, "数值")
                TextFieldValue(unit, { unit = it }, "单位")
                TextFieldValue(note, { note = it }, "备注")
            }
        },
        confirmButton = { TextButton(enabled = valid, onClick = { onSave(LocalDate.parse(date), item, value.toDouble(), unit, note) }) { Text("保存") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}

private data class VenueInfo(val name: String, val hours: String, val booking: String, val fee: String, val note: String)

@Composable
fun VenueOpeningsScreen(onBack: () -> Unit) {
    val venues = listOf(
        VenueInfo("西区操场", "全天开放，上课时段封闭", "操场、篮球、网球和排球场日常无需预约", "校内师生免费", "课程和大型活动期间以现场安排为准"),
        VenueInfo("西区看台乒乓球", "工作日 17:30–22:00；周末 15:30–22:00", "无需预约", "以现场公示为准", "开放时间可能随教学安排调整"),
        VenueInfo("田家炳体育馆羽毛球", "按预约场次开放", "需通过企业微信预约", "设免费与收费时段", "预约规则和价格以企业微信页面为准"),
        VenueInfo("昊海健身房", "08:30–22:00", "到场前确认当日安排", "以现场公示为准", "节假日开放时间可能调整"),
        VenueInfo("东四多功能大厅", "工作日 08:00–22:00；周末 09:00–22:00", "羽毛球 6 块、乒乓球 12 块，部分时段需预约", "设免费与收费时段", "具体价格和预约链路以学校最新通知为准"),
    )
    LeafySecondaryScaffold(title = "场馆开放", onBack = onBack) { contentModifier ->
        LazyColumn(
            modifier = contentModifier,
            contentPadding = PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item { LeafyStatusBanner("以下为北林静态说明，不代表实时占用情况；出发前请以场馆现场和学校通知为准。", isError = false) }
            items(venues, key = { it.name }) { venue ->
                Surface(color = MaterialTheme.leafySurfaces.content, shape = MaterialTheme.shapes.large) {
                    Column(modifier = Modifier.padding(LeafySpacing.card), verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny)) {
                        Text(venue.name, style = MaterialTheme.typography.titleMedium)
                        Text(venue.hours)
                        Text(venue.booking, style = MaterialTheme.typography.bodySmall)
                        Text(venue.fee, style = MaterialTheme.typography.bodySmall)
                        Text(venue.note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

private enum class MedicalSection(val title: String) { POLICY("政策"), GUIDE("报销指引"), LEDGER("台账") }

@Composable
fun MedicalScreen(
    onBack: () -> Unit,
    available: Boolean,
    viewModel: MedicalViewModel = viewModel(factory = appViewModelFactory { MedicalViewModel(it.campusLifeRepository) }),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var section by rememberSaveable { mutableStateOf(MedicalSection.POLICY) }
    var editorVisible by rememberSaveable { mutableStateOf(false) }
    var photoEntryId by rememberSaveable { mutableStateOf<String?>(null) }
    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        val entryId = photoEntryId
        photoEntryId = null
        if (uri != null && entryId != null) viewModel.importPhoto(entryId, uri)
    }
    LaunchedEffect(state.exportedFile) {
        val file = state.exportedFile ?: return@LaunchedEffect
        runCatching {
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                type = "text/csv"
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri("医疗报销台账", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, "分享医疗台账"))
        }
        viewModel.consumeExport()
    }
    LeafySecondaryScaffold(
        title = "医疗事项",
        onBack = onBack,
        actions = {
            if (available && section == MedicalSection.LEDGER) {
                LeafyActionIconButton(onClick = viewModel::export) { Icon(Icons.Outlined.FileUpload, "导出医疗台账") }
                LeafyActionIconButton(onClick = { editorVisible = true }) { Icon(Icons.Filled.Add, "新增医疗台账") }
            }
        },
    ) { contentModifier ->
        if (!available) {
            Box(modifier = contentModifier, contentAlignment = Alignment.Center) {
                LeafyEmptyState("当前校园暂不支持医疗事项", "该页面仅在校园提供 medicalServices 能力时开放。", icon = Icons.Outlined.LocalHospital)
            }
        } else {
            Column(modifier = contentModifier.padding(horizontal = LeafySpacing.page)) {
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    MedicalSection.entries.forEachIndexed { index, item ->
                        SegmentedButton(
                            selected = section == item,
                            onClick = { section = item },
                            shape = SegmentedButtonDefaults.itemShape(index, MedicalSection.entries.size),
                            modifier = Modifier.weight(1f),
                            label = { Text(item.title) },
                        )
                    }
                }
                when (section) {
                    MedicalSection.POLICY -> MedicalPolicyContent(Modifier.weight(1f))
                    MedicalSection.GUIDE -> MedicalGuideContent(Modifier.weight(1f))
                    MedicalSection.LEDGER -> MedicalLedgerContent(
                        entries = state.entries,
                        photos = state.photos,
                        onDelete = viewModel::delete,
                        onAddPhoto = { entryId ->
                            photoEntryId = entryId
                            photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
    if (editorVisible) {
        MedicalEditorDialog(
            onDismiss = { editorVisible = false },
            onSave = { viewModel.save(it); editorVisible = false },
        )
    }
}

@Composable
private fun MedicalPolicyContent(modifier: Modifier) {
    LazyColumn(modifier = modifier, contentPadding = PaddingValues(vertical = LeafySpacing.page), verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
        item { LeafyStatusBanner("政策会随学校和医保规则变化。这里提供办事整理，办理前请以校医院、学校通知与医保经办机构最新口径为准。", isError = false) }
        item { LeafySectionHeader("信息来源", supportingText = "北京林业大学校医院公开说明、学校通知及北京市医保办事指南。") }
        item { Text("应用不判断医学诊断，也不会把台账上传到 MyLeafy 或 Supabase。紧急情况请直接联系 120。") }
    }
}

@Composable
private fun MedicalGuideContent(modifier: Modifier) {
    var scenario by rememberSaveable { mutableStateOf("校医院门急诊") }
    var amount by rememberSaveable { mutableStateOf("") }
    val scenarios = listOf("校医院门急诊", "合同医院门急诊", "非合同/专科门急诊", "住院", "急危重症", "异地急诊")
    val ratio = when (scenario) {
        "校医院门急诊" -> 0.90
        "合同医院门急诊" -> 0.80
        "非合同/专科门急诊" -> 0.70
        "住院" -> 0.95
        else -> null
    }
    val detail = when (scenario) {
        "校医院门急诊" -> "先使用校园身份就诊；保留收费票据、费用明细、处方和门急诊病历。"
        "合同医院门急诊" -> "通常先取得校医院转诊单；准备转诊单、病历、处方、票据和费用明细。"
        "非合同/专科门急诊" -> "确认专科或转诊条件；准备诊断证明、病历、票据、费用明细和相关说明。"
        "住院" -> "保留住院病案首页、出院记录、费用清单、住院票据和医保结算材料。"
        else -> "优先救治并完整留存急诊诊断、病历、票据和费用明细；此情景按政策审核，不在应用内承诺比例。"
    }
    LazyColumn(modifier = modifier, contentPadding = PaddingValues(vertical = LeafySpacing.page), verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
        item { LazyRow(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) { items(scenarios) { FilterChip(scenario == it, { scenario = it }, { Text(it) }) } } }
        item { LeafySectionHeader(scenario, supportingText = "办事清单会随情景变化") }
        item {
            TextFieldValue(amount, { amount = it.filter { char -> char.isDigit() || char == '.' } }, "费用金额（可选）")
        }
        item {
            Text(
                ratio?.let { value ->
                    val estimate = amount.toDoubleOrNull()?.times(value)
                    "政策参考比例 ${(value * 100).toInt()}%" + (estimate?.let { " · 预计报销 ¥%.2f".format(it) } ?: "")
                } ?: "此情景无固定比例，需按政策材料审核",
                color = MaterialTheme.colorScheme.primary,
            )
        }
        item { Text(detail) }
        item { Text("通用材料：校园身份证明、本人银行卡信息、就诊病历、有效票据、费用明细。", color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

@Composable
private fun MedicalLedgerContent(
    entries: List<MedicalLedgerEntryEntity>,
    photos: List<MedicalLedgerPhotoEntity>,
    onDelete: (MedicalLedgerEntryEntity) -> Unit,
    onAddPhoto: (String) -> Unit,
    modifier: Modifier,
) {
    LazyColumn(modifier = modifier, contentPadding = PaddingValues(vertical = LeafySpacing.page), verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
        if (entries.isEmpty()) item { LeafyEmptyState("还没有报销台账", "点击右上角添加，本机保存就诊与材料进度。", icon = Icons.Outlined.LocalHospital) }
        items(entries, key = { it.id }) { entry ->
            Row(modifier = Modifier.fillMaxWidth().padding(vertical = LeafySpacing.micro), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(entry.hospitalName, style = MaterialTheme.typography.titleSmall)
                    Text("${LocalDate.ofEpochDay(entry.visitDate)} · ${entry.scenario} · ¥${entry.totalExpense}", style = MaterialTheme.typography.bodySmall)
                    Text(entry.status, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall)
                    Text("凭证照片 ${photos.count { it.entryId == entry.id }} 张", style = MaterialTheme.typography.bodySmall)
                }
                TextButton(onClick = { onAddPhoto(entry.id) }) { Text("加照片") }
                LeafyActionIconButton(onClick = { onDelete(entry) }) { Icon(Icons.Outlined.Delete, "删除医疗台账") }
            }
        }
    }
}

@Composable
private fun MedicalEditorDialog(onDismiss: () -> Unit, onSave: (MedicalLedgerDraft) -> Unit) {
    var date by remember { mutableStateOf(LocalDate.now().toString()) }
    var hospital by remember { mutableStateOf("") }
    var department by remember { mutableStateOf("") }
    var diagnosis by remember { mutableStateOf("") }
    var expense by remember { mutableStateOf("") }
    var materials by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    val valid = runCatching { LocalDate.parse(date) }.isSuccess && hospital.isNotBlank() && expense.toDoubleOrNull() != null
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("新增医疗台账") },
        text = {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
                item { TextFieldValue(date, { date = it }, "就诊日期（YYYY-MM-DD）") }
                item { TextFieldValue(hospital, { hospital = it }, "医院") }
                item { TextFieldValue(department, { department = it }, "科室") }
                item { TextFieldValue(diagnosis, { diagnosis = it }, "诊断摘要") }
                item { TextFieldValue(expense, { expense = it }, "总费用") }
                item { TextFieldValue(materials, { materials = it }, "材料清单") }
                item { TextFieldValue(note, { note = it }, "备注") }
            }
        },
        confirmButton = {
            TextButton(enabled = valid, onClick = {
                onSave(MedicalLedgerDraft(visitDate = LocalDate.parse(date), hospitalName = hospital, department = department, diagnosis = diagnosis, totalExpense = expense.toDouble(), materials = materials, note = note))
            }) { Text("保存") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}

@Composable
private fun TextFieldValue(value: String, onValueChange: (String) -> Unit, label: String) {
    OutlinedTextField(value, onValueChange, label = { Text(label) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
}

@Composable
private fun NumberField(value: String, onValueChange: (String) -> Unit, label: String) {
    OutlinedTextField(value, { onValueChange(it.filter(Char::isDigit)) }, label = { Text(label) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
}

@Composable
private fun sportsViewModel(): SportsViewModel = viewModel(
    factory = appViewModelFactory { SportsViewModel(it.campusLifeRepository) },
)

private fun parseWeekSet(raw: String): Set<Int> = raw.split(',').mapNotNull { it.trim().toIntOrNull() }.toSet()

private fun weekForDate(date: LocalDate): Int =
    (ChronoUnit.DAYS.between(SemesterConfig.current.semesterStartDate, date) / 7 + 1).toInt()
