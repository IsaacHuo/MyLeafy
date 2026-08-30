package com.myleafy.android.features.schedule

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

data class MemoDraft(
    val id: String? = null,
    val title: String = "",
    val body: String = "",
    val tags: List<String> = emptyList(),
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MemoEditorSheet(
    initial: MemoDraft,
    mutationState: ScheduleMutationState,
    onSave: (MemoDraft) -> Unit,
    onDelete: ((String) -> Unit)?,
    onConsumeMutation: () -> Unit,
    onDismiss: () -> Unit,
) {
    var title by rememberSaveable(initial.id) { mutableStateOf(initial.title) }
    var body by rememberSaveable(initial.id) { mutableStateOf(initial.body) }
    var tags by rememberSaveable(initial.id) { mutableStateOf(initial.tags.joinToString("、")) }
    var confirmsDelete by rememberSaveable { mutableStateOf(false) }
    val isSaving = mutationState is ScheduleMutationState.Saving
    val isEmpty = title.isBlank() && body.isBlank()

    LaunchedEffect(mutationState) {
        if (mutationState is ScheduleMutationState.Success) {
            onConsumeMutation()
            onDismiss()
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = if (initial.id == null) "新建随记" else "编辑随记",
                style = MaterialTheme.typography.headlineSmall,
            )
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("标题") },
                singleLine = true,
            )
            OutlinedTextField(
                value = body,
                onValueChange = { body = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("正文") },
                minLines = 6,
            )
            OutlinedTextField(
                value = tags,
                onValueChange = { tags = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("标签") },
                supportingText = { Text("用逗号、顿号或换行分隔") },
            )
            if (isEmpty) {
                Text("标题和正文至少填写一项", color = MaterialTheme.colorScheme.error)
            }
            (mutationState as? ScheduleMutationState.Error)?.let {
                Text(it.message, color = MaterialTheme.colorScheme.error)
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(bottom = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (initial.id != null && onDelete != null) {
                    TextButton(onClick = { confirmsDelete = true }, enabled = !isSaving) {
                        Text("删除", color = MaterialTheme.colorScheme.error)
                    }
                }
                Button(
                    onClick = {
                        onSave(
                            MemoDraft(
                                id = initial.id,
                                title = title.trim(),
                                body = body.trim(),
                                tags = tags.split(',', '，', '、', '\n')
                                    .map(String::trim)
                                    .filter(String::isNotEmpty),
                            ),
                        )
                    },
                    enabled = !isEmpty && !isSaving,
                    modifier = Modifier.weight(1f),
                ) { Text(if (isSaving) "保存中…" else "保存") }
            }
        }
    }

    if (confirmsDelete && initial.id != null && onDelete != null) {
        AlertDialog(
            onDismissRequest = { confirmsDelete = false },
            title = { Text("删除这条随记？") },
            text = { Text("随记会移入软删除状态，本阶段暂不提供回收站恢复。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmsDelete = false
                        onDelete(initial.id)
                    },
                ) { Text("删除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmsDelete = false }) { Text("取消") } },
        )
    }
}
