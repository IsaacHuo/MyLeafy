package com.myleafy.android.features.timetable.sharing

import android.content.ClipData
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.services.supabase.SharedTimetableSnapshotDto
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces

private enum class SharingSection(val title: String) { MINE("我的共享"), RECEIVED("他人课表") }

@Composable
fun TimetableSharingScreen(
    onBack: () -> Unit,
    initialCode: String? = null,
    viewModel: TimetableSharingViewModel = viewModel(
        factory = appViewModelFactory { TimetableSharingViewModel(it.timetableSharingRepository) },
    ),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var section by rememberSaveable { mutableStateOf(if (initialCode.isNullOrBlank()) SharingSection.MINE else SharingSection.RECEIVED) }
    LaunchedEffect(initialCode) { viewModel.setInitialCode(initialCode) }
    LeafySecondaryScaffold(
        title = "共享课表",
        onBack = onBack,
        actions = {
            LeafyActionIconButton(onClick = viewModel::refresh, enabled = !state.loading) {
                Icon(Icons.Outlined.Refresh, contentDescription = "刷新共享课表")
            }
        },
    ) { contentModifier ->
        Column(modifier = contentModifier.padding(horizontal = LeafySpacing.page)) {
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SharingSection.entries.forEachIndexed { index, item ->
                    SegmentedButton(
                        selected = section == item,
                        onClick = { section = item },
                        shape = SegmentedButtonDefaults.itemShape(index, SharingSection.entries.size),
                        modifier = Modifier.weight(1f),
                        label = { Text(item.title) },
                    )
                }
            }
            state.error?.let { LeafyStatusBanner(it, isError = true) }
            state.message?.let { LeafyStatusBanner(it, isError = false) }
            if (state.loading) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else if (section == SharingSection.MINE) {
                MySharingContent(state, viewModel, Modifier.weight(1f))
            } else {
                ReceivedSharingContent(state, viewModel, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun MySharingContent(state: TimetableSharingUiState, viewModel: TimetableSharingViewModel, modifier: Modifier) {
    val context = LocalContext.current
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(vertical = LeafySpacing.compact),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        item {
            Surface(color = MaterialTheme.leafySurfaces.content, shape = MaterialTheme.shapes.large) {
                Column(modifier = Modifier.padding(LeafySpacing.card), verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                    Text(if (state.mine == null) "尚未发布" else "已发布 ${state.mine.course_count} 门课程", style = MaterialTheme.typography.titleMedium)
                    Text("只上传课程名称、教师、地点、周次、节次和学期；成绩、考试、备注、提醒与背景不会上传。", style = MaterialTheme.typography.bodySmall)
                    Button(onClick = viewModel::publish, enabled = !state.mutating, modifier = Modifier.fillMaxWidth()) {
                        Text(if (state.mine == null) "发布当前学期课表" else "更新已发布课表")
                    }
                    OutlinedButton(onClick = viewModel::createInvite, enabled = state.mine != null && !state.mutating, modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Outlined.Share, contentDescription = null)
                        Text("生成单次邀请码")
                    }
                }
            }
        }
        state.latestCode?.let { code ->
            item {
                Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.large) {
                    Row(modifier = Modifier.fillMaxWidth().padding(LeafySpacing.card), verticalAlignment = Alignment.CenterVertically) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(code, style = MaterialTheme.typography.headlineSmall)
                            Text("7 天内有效，接受一次后失效", style = MaterialTheme.typography.bodySmall)
                        }
                        LeafyActionIconButton(onClick = {
                            val clipboard = context.getSystemService(android.content.ClipboardManager::class.java)
                            clipboard.setPrimaryClip(ClipData.newPlainText("MyLeafy 课表邀请码", code))
                        }) { Icon(Icons.Outlined.ContentCopy, "复制邀请码") }
                    }
                }
            }
        }
        item { LeafySectionHeader("访问成员", supportingText = "可逐个撤销，也可停止全部共享。") }
        if (state.members.isEmpty()) {
            item { LeafyEmptyState("还没有访问成员", "生成邀请码并由同学接受后会显示在这里。", icon = Icons.Outlined.Groups) }
        } else {
            items(state.members, key = { it.id }) { member ->
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("成员 ${member.viewer_id.take(8)}", modifier = Modifier.weight(1f))
                    TextButton(onClick = { viewModel.revoke(member.viewer_id) }, enabled = !state.mutating) { Text("撤销") }
                }
            }
            item { OutlinedButton(onClick = viewModel::stopSharing, enabled = !state.mutating, modifier = Modifier.fillMaxWidth()) { Text("停止全部共享") } }
        }
    }
}

@Composable
private fun ReceivedSharingContent(state: TimetableSharingUiState, viewModel: TimetableSharingViewModel, modifier: Modifier) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(vertical = LeafySpacing.compact),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        item {
            OutlinedTextField(
                value = state.acceptCode,
                onValueChange = viewModel::setAcceptCode,
                label = { Text("12 位邀请码") },
                supportingText = { Text("仅支持 A–Z 和 2–7") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item { Button(onClick = viewModel::accept, enabled = state.acceptCode.length == 12 && !state.mutating, modifier = Modifier.fillMaxWidth()) { Text("接受邀请码") } }
        if (state.viewable.isEmpty()) {
            item { LeafyEmptyState("还没有他人共享课表", "输入邀请码后会在本机只读展示。") }
        } else {
            items(state.viewable, key = { it.id }) { snapshot -> SharedSnapshotCard(snapshot, { viewModel.leave(snapshot.owner_id) }) }
        }
    }
}

@Composable
private fun SharedSnapshotCard(snapshot: SharedTimetableSnapshotDto, onLeave: () -> Unit) {
    Surface(color = MaterialTheme.leafySurfaces.content, shape = MaterialTheme.shapes.large) {
        Column(modifier = Modifier.fillMaxWidth().padding(LeafySpacing.card), verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny)) {
            Text("共享者 ${snapshot.owner_id.take(8)}", style = MaterialTheme.typography.titleMedium)
            Text("${snapshot.semester_id} · ${snapshot.course_count} 门课程", style = MaterialTheme.typography.bodySmall)
            snapshot.courses.sortedWith(compareBy({ it.day_of_week }, { it.duration.firstOrNull() ?: 0 })).take(8).forEach { course ->
                Text("周${course.day_of_week} ${course.duration.joinToString("-")}节 · ${course.course_name} · ${course.location.ifBlank { course.room }}", style = MaterialTheme.typography.bodySmall)
            }
            if (snapshot.courses.size > 8) Text("另有 ${snapshot.courses.size - 8} 门课程", style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = onLeave, modifier = Modifier.align(Alignment.End)) { Text("离开共享") }
        }
    }
}
