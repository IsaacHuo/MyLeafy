package com.myleafy.android.features.schedule

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExperimentalMaterial3Api
import com.myleafy.android.ui.components.LeafyTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyModalBottomSheet
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySheetContent
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafySpacing

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

    val dirty = title != initial.title || body != initial.body || tags != initial.tags.joinToString("、")
    val requestExit = com.myleafy.android.ui.components.rememberEditorExit(dirty, isSaving, onDismiss)
    val sheetState = androidx.compose.material3.rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { target ->
            if (target == androidx.compose.material3.SheetValue.Hidden && (dirty || isSaving)) {
                requestExit()
                false
            } else true
        },
    )
    LeafyModalBottomSheet(
        sheetState = sheetState,
        onDismissRequest = requestExit,
    ) {
        LeafySheetContent(
            modifier = Modifier.verticalScroll(rememberScrollState()),
            titleContent = {
                Text(
                    text = if (initial.id == null) "新建随记" else "编辑随记",
                    style = MaterialTheme.typography.headlineSmall,
                )
            },
        ) {
            LeafyTextField(
                enabled = !isSaving,
                value = title,
                onValueChange = { title = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("标题") },
                singleLine = true,
            )
            LeafyTextField(
                enabled = !isSaving,
                value = body,
                onValueChange = { body = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("正文") },
                minLines = 6,
            )
            LeafyTextField(
                enabled = !isSaving,
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
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
            ) {
                if (initial.id != null && onDelete != null) {
                    LeafyTextButton(onClick = { confirmsDelete = true }, enabled = !isSaving) {
                        Text("删除", color = MaterialTheme.colorScheme.error)
                    }
                }
                LeafyPrimaryButton(
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
        LeafyAlertDialog(
            onDismissRequest = { confirmsDelete = false },
            title = { Text("移到回收站？") },
            text = { Text("这条随记会移到回收站，你可以稍后恢复。") },
            confirmButton = {
                LeafyTextButton(
                    onClick = {
                        confirmsDelete = false
                        onDelete(initial.id)
                    },
                ) { Text("移到回收站", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { LeafyTextButton(onClick = { confirmsDelete = false }) { Text("取消") } },
        )
    }
}

internal val memoDraftSaver = androidx.compose.runtime.saveable.Saver<MemoDraft?, List<String>>(
    save = { draft -> draft?.let { listOf(it.id.orEmpty(), it.title, it.body) + it.tags } },
    restore = { values -> MemoDraft(values[0].ifBlank { null }, values[1], values[2], values.drop(3)) },
)
