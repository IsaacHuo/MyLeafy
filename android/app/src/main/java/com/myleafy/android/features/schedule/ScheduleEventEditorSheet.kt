package com.myleafy.android.features.schedule

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyModalBottomSheet
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySheetContent
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafySpacing
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleEventEditorSheet(
    initial: ScheduleEventDraft,
    mutationState: ScheduleMutationState,
    onSave: (ScheduleEventDraft) -> Unit,
    onDelete: ((String) -> Unit)?,
    onConsumeMutation: () -> Unit,
    onDismiss: () -> Unit,
) {
    var title by rememberSaveable(initial.id) { mutableStateOf(initial.title) }
    var date by remember(initial.id) { mutableStateOf(initial.date) }
    var startsAt by remember(initial.id) { mutableStateOf(initial.startsAt) }
    var endsAt by remember(initial.id) { mutableStateOf(initial.endsAt) }
    var location by rememberSaveable(initial.id) { mutableStateOf(initial.location) }
    var note by rememberSaveable(initial.id) { mutableStateOf(initial.note) }
    var confirmsDelete by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    val isSaving = mutationState is ScheduleMutationState.Saving
    val localValidation = when {
        title.isBlank() -> "请填写日程标题"
        !endsAt.isAfter(startsAt) -> "结束时间必须晚于开始时间"
        else -> null
    }

    LaunchedEffect(mutationState) {
        if (mutationState is ScheduleMutationState.Success) {
            onConsumeMutation()
            onDismiss()
        }
    }

    LeafyModalBottomSheet(
        onDismissRequest = onDismiss,
    ) {
        LeafySheetContent(
            modifier = Modifier.verticalScroll(rememberScrollState()),
            titleContent = {
                Text(
                text = if (initial.id == null) "添加个人日程" else "编辑个人日程",
                style = MaterialTheme.typography.headlineSmall,
                )
            },
        ) {
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("标题 *") },
                singleLine = true,
            )
            FilledTonalButton(
                onClick = {
                    DatePickerDialog(
                        context,
                        { _, year, month, day -> date = LocalDate.of(year, month + 1, day) },
                        date.year,
                        date.monthValue - 1,
                        date.dayOfMonth,
                    ).show()
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("日期  ${date.format(dateFormatter)}")
            }
            Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                OutlinedButton(
                    onClick = {
                        TimePickerDialog(
                            context,
                            { _, hour, minute -> startsAt = LocalTime.of(hour, minute) },
                            startsAt.hour,
                            startsAt.minute,
                            true,
                        ).show()
                    },
                    modifier = Modifier.weight(1f),
                ) { Text("开始 ${startsAt.format(timeFormatter)}") }
                OutlinedButton(
                    onClick = {
                        TimePickerDialog(
                            context,
                            { _, hour, minute -> endsAt = LocalTime.of(hour, minute) },
                            endsAt.hour,
                            endsAt.minute,
                            true,
                        ).show()
                    },
                    modifier = Modifier.weight(1f),
                ) { Text("结束 ${endsAt.format(timeFormatter)}") }
            }
            OutlinedTextField(
                value = location,
                onValueChange = { location = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("地点") },
                singleLine = true,
            )
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("备注") },
                minLines = 3,
                maxLines = 6,
            )
            localValidation?.let {
                Text(text = it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            (mutationState as? ScheduleMutationState.Error)?.let {
                Text(text = it.message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
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
                            ScheduleEventDraft(
                                id = initial.id,
                                title = title,
                                date = date,
                                startsAt = startsAt,
                                endsAt = endsAt,
                                location = location,
                                note = note,
                            ),
                        )
                    },
                    enabled = localValidation == null && !isSaving,
                    modifier = Modifier.weight(1f),
                ) {
                    Text(if (isSaving) "保存中…" else "保存")
                }
            }
        }
    }

    if (confirmsDelete && initial.id != null && onDelete != null) {
        LeafyAlertDialog(
            onDismissRequest = { confirmsDelete = false },
            title = { Text("删除这条日程？") },
            text = { Text("删除后会同时从课表和日迹日程列表移除。") },
            confirmButton = {
                LeafyTextButton(
                    onClick = {
                        confirmsDelete = false
                        onDelete(initial.id)
                    },
                    modifier = Modifier
                        .testTag("confirm-delete-schedule")
                        .semantics { contentDescription = "确认删除日程" },
                ) { Text("删除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                LeafyTextButton(onClick = { confirmsDelete = false }) { Text("取消") }
            },
        )
    }
}

private val dateFormatter = DateTimeFormatter.ofPattern("yyyy年M月d日")
private val timeFormatter = DateTimeFormatter.ofPattern("HH:mm")
