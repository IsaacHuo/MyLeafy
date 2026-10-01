package com.myleafy.android.features.campus

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.core.data.local.SunshineReminderEntity
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.ui.components.*
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.launch
import java.time.LocalDate

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
@Composable fun SunshineRunScreen(onBack: () -> Unit, viewModel: SportsViewModel = sportsViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val saving by viewModel.saving.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val container = (context.applicationContext as MyLeafyApplication).container
    val identity by container.activeAppScopeStore.scope.collectAsStateWithLifecycle()
    val reminder by remember { container.activeAppScopeStore.scope.flatMapLatest { container.campusPersonalDao.reminder(it.scopeKey) } }.collectAsStateWithLifecycle(null)
    val owner = rememberCoroutineScope()
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (!granted) viewModel.reportError("通知权限未开启，长跑提醒无法发送")
        else owner.launch { try { container.sunshineReminderScheduler.reconcile() } catch (failure: Exception) { if (failure is kotlinx.coroutines.CancellationException) throw failure; viewModel.reportError(failure.message ?: "提醒排期失败") } }
    }
    var rules by rememberSaveable { mutableStateOf(false) }
    var date by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var reminderVisible by rememberSaveable { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<com.myleafy.android.core.data.local.SunshineRunRecordEntity?>(null) }
    val config = SemesterConfig.current
    val today = LocalDate.now(java.time.ZoneId.of("Asia/Shanghai"))
    val periods = remember(state.runs, state.settings, config) { SunshineRunPlanner.periods(state.runs, state.settings, config) }
    val current = SunshineRunPlanner.period(today, periods, config)
    val total = periods.sumOf { it.count }
    val selected = runCatching { LocalDate.parse(date) }.getOrNull()
    val selectedPeriod = selected?.let { SunshineRunPlanner.period(it, periods, config) }
    LeafySecondaryScaffold("阳光长跑", onBack = onBack, actions = {
        TextButton(enabled = !state.loading && !state.loadFailed, onClick = { rules = true }) { Text("规则") }
        TextButton(enabled = !state.loading && !state.loadFailed, onClick = { reminderVisible = true }) { Text("提醒") }
    }) { modifier -> LazyColumn(modifier, contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        error?.let { item { LeafyStatusBanner(it, isError = true, onDismiss = viewModel::dismissError) } }
        if (state.loading) { item { LeafyLoadingState() }; return@LazyColumn }
        if (state.loadFailed) { item { TextButton(onClick = viewModel::retryLoad) { Text("重新加载跑步记录") } }; return@LazyColumn }
        item {
            Text("有效记录 $total / ${state.settings.totalTarget} 次", style = MaterialTheme.typography.headlineSmall)
            Text("还需 ${(state.settings.totalTarget - total).coerceAtLeast(0)} 次 · ${config.semesterStartDate} 至 ${SunshineRunPlanner.semesterEnd(config)}")
            LinearProgressIndicator(progress = { (total.toFloat() / state.settings.totalTarget).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth())
            Text(current?.let { "本周期 ${it.count} / ${it.target} 次 · 有效周 ${it.weeks.joinToString("、")}" } ?: "今天不在有效跑步周内")
            val record = state.runs.firstOrNull { it.dateEpochDay == today.toEpochDay() }
            LeafyPrimaryButton(onClick = { if (record != null) viewModel.deleteRun(record) else current?.let { viewModel.addRun(today, it.weeks.first(), it.weeks.last()) } }, enabled = !saving && (current != null || record != null)) { Text(if (record == null) "记录今天" else "撤销今日记录") }
        }
        item {
            LeafySectionHeader("补记跑步")
            LeafyTextField(date, { date = it }, label = { Text("日期 YYYY-MM-DD") }, isError = selected == null, singleLine = true)
            TextButton(enabled = !saving && selected != null && selected <= today && selectedPeriod != null, onClick = { selectedPeriod?.let { viewModel.addRun(selected!!, it.weeks.first(), it.weeks.last()) } }) { Text("补记所选日期") }
            if (selected != null && selectedPeriod == null) Text("所选日期不在本学期有效周内")
        }
        item { LeafySectionHeader("全部周期进度") }
        items(periods, key = { it.index }) { period ->
            Text("第 ${period.index} 周期 · 有效周 ${period.weeks.joinToString("、")} · ${period.count} / ${period.target} 次")
            LinearProgressIndicator(progress = { (period.count.toFloat() / period.target).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth())
        }
        item { LeafySectionHeader("本地跑步记录", supportingText = "同一天只保留一条；排除周及学期外记录保留，但不计进度") }
        items(state.runs, key = { it.id }) { record -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(LocalDate.ofEpochDay(record.dateEpochDay).toString(), Modifier.padding(top = 12.dp)); TextButton(onClick = { deleting = record }) { Text("删除") }
        } }
    } }
    if (rules) SunshineRulesDialog(saving, error, state.settings.totalTarget, state.settings.weeksPerPeriod, state.settings.periodTarget, state.settings.excludedWeeks, state.settings.skipsExcludedWeeks, { rules = false }) { totalTarget, weeks, target, excluded, skipExcluded -> viewModel.saveRules(totalTarget, weeks, target, excluded, skipExcluded) { rules = false } }
    if (reminderVisible) SunshineReminderEditor(reminder ?: SunshineReminderEntity(identity.scopeKey), { reminderVisible = false }) { value -> owner.launch {
        try { check(value.scopeKey == container.activeAppScopeStore.current.scopeKey) { "账号已切换" }; container.campusPersonalDao.save(value); container.sunshineReminderScheduler.reconcile(); reminderVisible = false
            if (value.enabled && android.os.Build.VERSION.SDK_INT >= 33 && !androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled()) permission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        } catch (failure: Exception) { if (failure is kotlinx.coroutines.CancellationException) throw failure; viewModel.reportError(failure.message ?: "提醒保存失败") }
    } }
    deleting?.let { record -> LeafyAlertDialog(onDismissRequest = { deleting = null }, title = { Text("删除这次跑步记录？") }, confirmButton = { TextButton(onClick = { viewModel.deleteRun(record); deleting = null }) { Text("删除") } }, dismissButton = { TextButton(onClick = { deleting = null }) { Text("取消") } }) }
}

@Composable private fun SunshineReminderEditor(initial: SunshineReminderEntity, onDismiss: () -> Unit, onSave: (SunshineReminderEntity) -> Unit) {
    var enabled by rememberSaveable { mutableStateOf(initial.enabled) }
    var weekdays by rememberSaveable { mutableStateOf(initial.weekdays) }
    var hour by rememberSaveable { mutableStateOf(initial.hour.toString()) }
    var minute by rememberSaveable { mutableStateOf(initial.minute.toString()) }
    LeafyAlertDialog(onDismissRequest = onDismiss, title = { Text("本地长跑提醒") }, text = { Column {
        Row { Text("开启提醒", Modifier.weight(1f)); Switch(enabled, { enabled = it }) }
        Text("周期达标、当天已记录及排除周不会提醒；系统节电可能延迟投递。", style = MaterialTheme.typography.bodySmall)
        FlowRow { (1..7).forEach { day -> FilterChip(day.toString() in weekdays.split(','), { val values = weekdays.split(',').filter(String::isNotBlank); weekdays = (if (day.toString() in values) values - day.toString() else values + day.toString()).sorted().joinToString(",") }, { Text("周${listOf("一","二","三","四","五","六","日")[day - 1]}") }) } }
        LeafyTextField(hour, { hour = it }, label = { Text("时（0–23）") }); LeafyTextField(minute, { minute = it }, label = { Text("分（0–59）") })
    } }, confirmButton = { TextButton(enabled = hour.toIntOrNull() in 0..23 && minute.toIntOrNull() in 0..59 && (!enabled || weekdays.isNotBlank()), onClick = { onSave(initial.copy(enabled = enabled, weekdays = weekdays, hour = hour.toInt(), minute = minute.toInt())) }) { Text("保存") } }, dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } })
}
