package com.myleafy.android.features.schedule

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import com.myleafy.android.core.di.appViewModelFactory
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun ScheduleScreen(
    viewModel: ScheduleViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ScheduleViewModel(repository = container.scheduleRepository)
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()
    var memoInput by remember { mutableStateOf("") }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(20.dp),
    ) {
        Text(text = "日迹", style = MaterialTheme.typography.headlineMedium)
        Spacer(modifier = Modifier.height(12.dp))

        when (val state = uiState) {
            is ScheduleUiState.Loading -> {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            }

            is ScheduleUiState.Error -> {
                Text(
                    text = state.message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            is ScheduleUiState.Empty -> {
                Text(
                    text = "暂无随记或日程，写一条随记开始记录吧",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.outline,
                )
            }

            is ScheduleUiState.Loaded -> {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(12.dp)) {
                                OutlinedTextField(
                                    value = memoInput,
                                    onValueChange = { memoInput = it },
                                    modifier = Modifier.fillMaxWidth(),
                                    placeholder = { Text("写一条随记…") },
                                    maxLines = 3,
                                )
                                Spacer(modifier = Modifier.height(8.dp))
                                Button(
                                    onClick = {
                                        viewModel.addMemo(body = memoInput)
                                        memoInput = ""
                                    },
                                    enabled = memoInput.isNotBlank(),
                                ) {
                                    Text("添加随记")
                                }
                            }
                        }
                    }

                    items(state.memos, key = { it.id }) { memo ->
                        MemoRow(memo = memo, onDelete = { viewModel.deleteMemo(memo.id) })
                    }

                    if (state.events.isNotEmpty()) {
                        item {
                            Text(
                                text = "个人日程",
                                style = MaterialTheme.typography.titleSmall,
                                modifier = Modifier.padding(top = 12.dp),
                            )
                        }
                        items(state.events, key = { it.id }) { event ->
                            EventRow(event = event, onDelete = { viewModel.deleteEvent(event.id) })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MemoRow(memo: ScheduleMemoEntity, onDelete: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(start = 12.dp, top = 4.dp, bottom = 4.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = memo.title ?: memo.body,
                    style = MaterialTheme.typography.titleSmall,
                )
                if (memo.title != null) {
                    Text(
                        text = memo.body,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                    )
                }
            }
            IconButton(onClick = onDelete) {
                Icon(imageVector = Icons.Filled.Delete, contentDescription = "删除随记")
            }
        }
    }
}

@Composable
private fun EventRow(event: ScheduleEventEntity, onDelete: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(start = 12.dp, top = 4.dp, bottom = 4.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(text = event.title, style = MaterialTheme.typography.titleSmall)
                Text(
                    text = formatEpoch(event.startsAt) + (event.location?.let { " · $it" } ?: ""),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onDelete) {
                Icon(imageVector = Icons.Filled.Delete, contentDescription = "删除日程")
            }
        }
    }
}

private val eventFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("M月d日 HH:mm").withZone(ZoneId.systemDefault())

private fun formatEpoch(millis: Long): String = eventFormatter.format(Instant.ofEpochMilli(millis))
