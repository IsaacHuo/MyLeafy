package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.parsers.*
import com.myleafy.android.ui.components.*
import java.time.LocalDate

@Composable fun ClassroomScreen(onBack: () -> Unit,
    viewModel: ClassroomViewModel = viewModel(factory = appViewModelFactory { ClassroomViewModel(it.classroomRepository, personalDao = it.campusPersonalDao, scopes = it.activeAppScopeStore) }),
    modifier: Modifier = Modifier) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val favorites by viewModel.favorites.collectAsStateWithLifecycle(emptyList())
    var date by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var byRoom by rememberSaveable { mutableStateOf(false) }
    var start by rememberSaveable { mutableIntStateOf(1) }
    var end by rememberSaveable { mutableIntStateOf(1) }
    var selecting by rememberSaveable { mutableStateOf<String?>(null) }
    var building by rememberSaveable { mutableStateOf("全部") }
    var room by rememberSaveable { mutableStateOf("") }
    var collapsed by rememberSaveable { mutableStateOf(emptyList<String>()) }
    fun query() { viewModel.queryDate(LocalDate.parse(date), if (byRoom) 0 else start, end) }
    val validDate = runCatching { LocalDate.parse(date) }.isSuccess
    val validQuery = validDate && (!byRoom || building != "全部" && room.isNotBlank())
    LeafySecondaryScaffold("空闲教室", onBack = onBack, modifier = modifier) { content ->
        LazyColumn(content.fillMaxSize(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Row { FilterChip(!byRoom, { byRoom = false; viewModel.clearResults() }, { Text("按节次") }); Spacer(Modifier.width(8.dp)); FilterChip(byRoom, { byRoom = true; viewModel.clearResults() }, { Text("按教室") }) }
                LeafyTextField(date, { date = it; viewModel.clearResults() }, label = { Text("查询日期 YYYY-MM-DD") }, modifier = Modifier.fillMaxWidth(), singleLine = true, isError = !validDate)
                if (!byRoom) FlowRow {
                    OutlinedButton(onClick = { selecting = "start" }) { Text("第 $start 节起") }
                    OutlinedButton(onClick = { selecting = "end" }) { Text("第 $end 节止") }
                }
                val loaded = state as? ClassroomUiState.Loaded
                val buildings = (listOf("全部", "学研A座", "学研B座", "学研C座", "二教", "三教", "四教", "五教") + loaded?.matrix?.rows.orEmpty().map { it.room.building } + favorites.map { it.building }).distinct()
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { items(buildings) { name -> FilterChip(building == name, { building = name }, { Text(name) }) } }
                if (byRoom) {
                    LeafyTextField(room, { room = it.trim().uppercase() }, label = { Text("教室号") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                    val rooms = loaded?.matrix?.rows.orEmpty().filter { building == "全部" || it.room.building == building }.map { it.room.room }.distinct()
                    if (rooms.isNotEmpty()) LazyRow { items(rooms) { name -> TextButton(onClick = { room = name }) { Text(name) } } }
                }
                LeafyPrimaryButton(onClick = ::query, enabled = validQuery && state !is ClassroomUiState.Loading, modifier = Modifier.fillMaxWidth()) { Text(if (state is ClassroomUiState.Loading) "查询中…" else "查询") }
            }
            if (favorites.isNotEmpty()) item {
                Text("常用教室", style = MaterialTheme.typography.titleSmall)
                FlowRow { favorites.forEach { favorite -> TextButton(onClick = { building = favorite.building; room = favorite.room; byRoom = true; viewModel.clearResults() }) { Text("${favorite.building} ${favorite.room}") } } }
            }
            when (val result = state) {
                ClassroomUiState.Idle -> item { Text("选择日期与查询方式后点击查询") }
                ClassroomUiState.Loading -> item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                is ClassroomUiState.Error -> item { LeafyErrorState("查询失败", result.message, action = { TextButton(onClick = ::query, enabled = validQuery) { Text("重试") } }) }
                is ClassroomUiState.Loaded -> {
                    item { Text("${result.date} · ${if (byRoom) "全天第 1–12 节" else "第 $start–$end 节"}", style = MaterialTheme.typography.titleSmall) }
                    if (byRoom) {
                        val target = result.matrix?.rows?.firstOrNull { it.room.room == room && it.room.building == building }
                        if (target == null) item { Text("学校结果未包含所选教室，请选择教学楼和完整教室号") }
                        else {
                            item { TextButton(onClick = { viewModel.toggleFavorite(target.room) }) { Text(if (favorites.any { it.building == target.room.building && it.room == room }) "取消收藏" else "收藏教室") } }
                            items((1..12).toList()) { period ->
                                val slot = target.slots.firstOrNull { it.period == period }
                                val time = com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule.slot(period)
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text("第 $period 节 ${time?.startText.orEmpty()}–${time?.endText.orEmpty()}"); Text(slot?.status?.title ?: "待确认") }
                            }
                        }
                    } else {
                        val visible = result.rooms.filter { building == "全部" || it.building == building }
                        item { Text("共 ${visible.size} 间空闲教室") }
                        visible.groupBy { it.building }.forEach { (name, rooms) ->
                            item(key = name) {
                                LeafyContentSurface(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp)) {
                                    TextButton(onClick = { collapsed = if (name in collapsed) collapsed - name else collapsed + name }) { Text("$name · ${rooms.size} 间 ${if (name in collapsed) "›" else "⌄"}") }
                                    if (name !in collapsed) FlowRow { rooms.forEach { target ->
                                        TextButton(onClick = { viewModel.toggleFavorite(target) }) { Text("${target.room} ${if (favorites.any { it.building == name && it.room == target.room }) "★" else "☆"}") }
                                    } }
                                } }
                            }
                        }
                    }
                }
            }
        }
    }
    selecting?.let { selection -> LeafyAlertDialog(onDismissRequest = { selecting = null }, title = { Text("选择节次") }, text = {
        LazyColumn { items(12) { index -> val value = index + 1
            TextButton(onClick = { if (selection == "start") { start = value; if (end < start) end = start } else { end = value; if (start > end) start = end }; selecting = null; viewModel.clearResults() }, modifier = Modifier.fillMaxWidth()) { Text("第 $value 节") }
        } }
    }, confirmButton = { TextButton(onClick = { selecting = null }) { Text("取消") } }) }
}
