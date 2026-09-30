package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.ui.components.*
import java.time.LocalDate

@Composable
fun ClassroomScreen(onBack: () -> Unit,
    viewModel: ClassroomViewModel = viewModel(factory = appViewModelFactory { ClassroomViewModel(it.classroomRepository) }),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var week by rememberSaveable { mutableIntStateOf(viewModel.currentWeek) }
    var day by rememberSaveable { mutableIntStateOf(LocalDate.now().dayOfWeek.value) }
    var choosingWeek by rememberSaveable { mutableStateOf(false) }
    var choosingDay by rememberSaveable { mutableStateOf(false) }
    val weekdays = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
    fun query() = viewModel.query(week, day, startPeriod = 1, endPeriod = 12)
    LeafySecondaryScaffold(title = "空闲教室", onBack = onBack, modifier = modifier) { contentModifier ->
        LazyColumn(modifier = contentModifier.fillMaxSize(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedButton(onClick = { choosingWeek = true }) { Text("第 $week 周 ▾") }
                    OutlinedButton(onClick = { choosingDay = true }) { Text("${weekdays[day - 1]} ▾") }
                }
                Text("全天 · 第 1–12 节", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                LeafyPrimaryButton(onClick = ::query, enabled = uiState !is ClassroomUiState.Loading, modifier = Modifier.fillMaxWidth().padding(top = 12.dp)) {
                    Text(if (uiState is ClassroomUiState.Loading) "查询中…" else "查询空闲教室")
                }
            }
            when (val state = uiState) {
                is ClassroomUiState.Idle -> item { Text("选择周次与星期后查询", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                is ClassroomUiState.Loading -> item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                is ClassroomUiState.Error -> item { LeafyErrorState("查询失败", state.message, action = { LeafyTextButton(onClick = ::query) { Text("重试") } }) }
                is ClassroomUiState.Loaded -> {
                    item { Text("第 $week 周 · ${weekdays[day - 1]} · 共 ${state.rooms.size} 间", style = MaterialTheme.typography.titleSmall) }
                    if (state.rooms.isEmpty()) item { LeafyEmptyState("没有空闲教室", "学校在所选周次与星期未返回可用教室。") }
                    state.rooms.groupBy { it.building }.forEach { (building, rooms) ->
                        item(key = building) {
                            Surface(modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text(building, style = MaterialTheme.typography.titleMedium)
                                    FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        rooms.distinctBy { it.room }.forEach { Text(it.room, modifier = Modifier.padding(vertical = 6.dp)) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if (choosingWeek || choosingDay) {
        val weeks = choosingWeek
        LeafyAlertDialog(onDismissRequest = { choosingWeek = false; choosingDay = false }, title = { Text(if (weeks) "选择周次" else "选择星期") }, text = {
            LazyColumn { items(if (weeks) SemesterConfig.supportedWeeks else 7) { index ->
                LeafyTextButton(onClick = {
                    if (weeks && week != index + 1) { week = index + 1; viewModel.clearResults() }
                    if (!weeks && day != index + 1) { day = index + 1; viewModel.clearResults() }
                    choosingWeek = false; choosingDay = false
                }, modifier = Modifier.fillMaxWidth()) { Text(if (weeks) "第 ${index + 1} 周" else weekdays[index]) }
            } }
        }, confirmButton = { LeafyTextButton(onClick = { choosingWeek = false; choosingDay = false }) { Text("取消") } })
    }
}
