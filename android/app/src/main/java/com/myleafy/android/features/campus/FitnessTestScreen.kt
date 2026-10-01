package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.data.local.FitnessTestRecordEntity
import com.myleafy.android.ui.components.*
import java.time.LocalDate
import kotlinx.coroutines.launch

internal val fitnessProjects = linkedMapOf("身高" to "cm", "体重" to "kg", "肺活量" to "ml", "50米" to "秒", "坐位体前屈" to "cm", "立定跳远" to "cm", "引体向上" to "次", "仰卧起坐" to "次", "800米" to "分秒", "1000米" to "分秒", "其他" to "次")
internal fun fitnessValue(record: FitnessTestRecordEntity): String = if (record.unit == "分秒") {
    val seconds = kotlin.math.floor(record.value + 0.5).toInt()
    "${seconds / 60}分${seconds % 60}秒"
} else "${if (record.value == record.value.toLong().toDouble()) record.value.toLong() else record.value} ${record.unit}"

@Composable fun FitnessTestScreen(onBack: () -> Unit, viewModel: SportsViewModel = sportsViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val saving by viewModel.saving.collectAsStateWithLifecycle()
    var showing by rememberSaveable { mutableStateOf(false) }
    var editing by remember { mutableStateOf<FitnessTestRecordEntity?>(null) }
    var deleting by remember { mutableStateOf<FitnessTestRecordEntity?>(null) }
    var filter by rememberSaveable { mutableStateOf("全部") }
    val context = LocalContext.current
    val owner = rememberCoroutineScope()
    val records = state.fitnessTests.filter { filter == "全部" || it.item.replace(" ", "") == filter.replace(" ", "") }
    LeafySecondaryScaffold("体测记录", onBack = onBack, actions = {
        TextButton(enabled = !state.loading && !state.loadFailed, onClick = { owner.launch { try { val file = campusTextImage(context, "fitness", "体测记录", state.fitnessTests.map { "${LocalDate.ofEpochDay(it.testedAt)} ${it.item} ${fitnessValue(it)} ${it.note}" }); shareCampusFile(context, file, "image/png") } catch (failure: Exception) { if (failure is kotlinx.coroutines.CancellationException) throw failure; viewModel.reportError(failure.message ?: "分享失败") } } }) { Text("分享") }
        TextButton(enabled = !state.loading && !state.loadFailed, onClick = { editing = null; showing = true }) { Text("新增") }
    }) { modifier -> LazyColumn(modifier, contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        error?.let { item { LeafyStatusBanner(it, isError = true, onDismiss = viewModel::dismissError) } }
        if (state.loading) { item { LeafyLoadingState() }; return@LazyColumn }
        if (state.loadFailed) { item { TextButton(onClick = viewModel::retryLoad) { Text("重新加载体测记录") } }; return@LazyColumn }
        item { Text("${state.fitnessTests.size} 条记录 · ${state.fitnessTests.map { it.item }.distinct().size} 个项目 · 最近 ${state.fitnessTests.maxOfOrNull { it.testedAt }?.let(LocalDate::ofEpochDay) ?: "暂无"}") }
        item { LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { items((listOf("全部") + fitnessProjects.keys + state.fitnessTests.map { it.item }).distinct()) { name -> FilterChip(filter == name, { filter = name }, { Text(name) }) } } }
        if (records.isEmpty()) item { Text("没有符合条件的记录") }
        items(records, key = { it.id }) { record -> LeafyContentSurface(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp)) {
            Text(record.item, style = MaterialTheme.typography.titleMedium); Text("${fitnessValue(record)} · ${LocalDate.ofEpochDay(record.testedAt)}")
            if (record.note.isNotBlank()) Text(record.note)
            Row { TextButton(onClick = { editing = record; showing = true }) { Text("编辑") }; TextButton(onClick = { deleting = record }) { Text("删除") } }
        } } }
    } }
    if (showing) FitnessEditor(editing, saving, error, { showing = false }) { date, item, value, unit, note -> viewModel.saveFitness(date, item, value, unit, note, editing?.id) { showing = false } }
    deleting?.let { record -> LeafyAlertDialog(onDismissRequest = { deleting = null }, title = { Text("删除体测记录？") }, confirmButton = { TextButton(onClick = { viewModel.deleteFitness(record); deleting = null }) { Text("删除") } }, dismissButton = { TextButton(onClick = { deleting = null }) { Text("取消") } }) }
}

@Composable private fun FitnessEditor(record: FitnessTestRecordEntity?, saving: Boolean, error: String?, onDismiss: () -> Unit, onSave: (LocalDate, String, Double, String, String) -> Unit) {
    var date by rememberSaveable { mutableStateOf(record?.testedAt?.let(LocalDate::ofEpochDay)?.toString() ?: LocalDate.now().toString()) }
    var item by rememberSaveable { mutableStateOf(record?.item ?: "1000米") }
    var unit by rememberSaveable { mutableStateOf(record?.unit ?: "分秒") }
    var value by rememberSaveable { mutableStateOf(record?.value?.toString().orEmpty()) }
    val initialSeconds = record?.value?.let { kotlin.math.floor(it + 0.5).toInt() }
    var minutes by rememberSaveable { mutableStateOf(initialSeconds?.div(60)?.toString().orEmpty()) }
    var seconds by rememberSaveable { mutableStateOf(initialSeconds?.rem(60)?.toString().orEmpty()) }
    var note by rememberSaveable { mutableStateOf(record?.note.orEmpty()) }
    val amount = if (unit == "分秒") minutes.toIntOrNull()?.takeIf { it in 0..20 }?.let { min -> seconds.toIntOrNull()?.takeIf { it in 0..59 }?.let { (min * 60 + it).toDouble() } } else value.toDoubleOrNull()
    val valid = runCatching { LocalDate.parse(date) }.isSuccess && item.isNotBlank() && unit.isNotBlank() && amount?.let { it.isFinite() && it > 0 } == true
    val initial = listOf(record?.testedAt?.let(LocalDate::ofEpochDay)?.toString() ?: LocalDate.now().toString(), record?.item ?: "1000米", record?.unit ?: "分秒", record?.value?.toString().orEmpty(), initialSeconds?.div(60)?.toString().orEmpty(), initialSeconds?.rem(60)?.toString().orEmpty(), record?.note.orEmpty())
    val exit = rememberEditorExit(listOf(date, item, unit, value, minutes, seconds, note) != initial, saving, onDismiss)
    LeafyAlertDialog(onDismissRequest = exit, title = { Text(if (record == null) "新增体测" else "编辑体测") }, text = {
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            error?.let { item { LeafyStatusBanner(it, isError = true) } }
            item { LeafyTextField(date, { date = it }, label = { Text("日期 YYYY-MM-DD") }) }
            item { FlowRow { fitnessProjects.forEach { (name, defaultUnit) -> FilterChip(item.replace(" ", "") == name, { item = name; unit = defaultUnit; value = ""; minutes = ""; seconds = "" }, { Text(name) }) } } }
            item { LeafyTextField(item, { item = it }, label = { Text("项目") }) }
            if (unit == "分秒") item { Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { LeafyTextField(minutes, { minutes = it }, modifier = Modifier.weight(1f), label = { Text("分") }); LeafyTextField(seconds, { seconds = it }, modifier = Modifier.weight(1f), label = { Text("秒") }) } }
            else item { LeafyTextField(value, { value = it }, label = { Text("数值") }) }
            item { LeafyTextField(unit, { unit = it }, label = { Text("单位") }) }
            item { LeafyTextField(note, { note = it }, label = { Text("备注") }) }
        }
    }, confirmButton = { TextButton(enabled = valid && !saving, onClick = { onSave(LocalDate.parse(date), item, amount!!, unit, note) }) { Text(if (saving) "保存中" else "保存") } }, dismissButton = { TextButton(onClick = exit) { Text("取消") } })
}
