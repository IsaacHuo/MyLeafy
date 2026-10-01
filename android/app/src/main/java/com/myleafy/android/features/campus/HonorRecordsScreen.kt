package com.myleafy.android.features.campus

import android.app.DatePickerDialog
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.SheetValue
import com.myleafy.android.ui.components.rememberEditorExit
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import com.myleafy.android.ui.components.LeafyTextField
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.data.local.HonorRecordEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyModalBottomSheet
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafySheetContent
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafySpacing
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val honorZone: ZoneId = ZoneId.of("Asia/Shanghai")

@Composable
fun HonorRecordsScreen(
    onBack: () -> Unit,
    viewModel: HonorRecordsViewModel = viewModel(
        factory = appViewModelFactory { container ->
            HonorRecordsViewModel(
                HonorRecordRepository(
                    container.applicationContext,
                    container.honorRecordDao,
                    container.activeAppScopeStore,
                ),
            )
        },
    ),
) {
    val records by viewModel.records.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val saving by viewModel.saving.collectAsStateWithLifecycle()
    val loadFailed by viewModel.loadFailed.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var preview by remember { mutableStateOf<HonorRecordEntity?>(null) }
    var editing by remember { mutableStateOf<HonorRecordEntity?>(null) }
    var pendingDelete by remember { mutableStateOf<HonorRecordEntity?>(null) }
    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris ->
        viewModel.importAll(uris)
    }

    LeafySecondaryScaffold(
        title = "荣誉记录",
        onBack = onBack,
        actions = {
            LeafyActionIconButton(onClick = {
                importLauncher.launch(arrayOf("application/pdf", "image/*"))
            }) { Icon(Icons.Filled.Add, contentDescription = "导入奖状证书") }
        },
    ) { contentModifier ->
        Column(modifier = contentModifier.fillMaxSize()) {
            message?.let { value ->
                LeafyStatusBanner(message = value, isError = true, onDismiss = viewModel::consumeMessage,
                        actionLabel = if (loadFailed) "重试" else null, onAction = if (loadFailed) viewModel::retryLoad else null)
            }
            if (records.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    LeafyEmptyState(
                        title = "暂无荣誉记录",
                        message = "导入奖状、证书等 PDF 或图片文件，文件仅保存在本机。",
                        icon = Icons.Outlined.Description,
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(LeafySpacing.page),
                    verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
                ) {
                    items(records, key = { it.id }) { record ->
                        Surface(
                            modifier = Modifier.fillMaxWidth(),
                            shape = MaterialTheme.shapes.large,
                            color = MaterialTheme.colorScheme.surface,
                        ) {
                            Column(modifier = Modifier.padding(LeafySpacing.card)) {
                                if (record.contentType.startsWith("image/")) coil.compose.AsyncImage(model = viewModel.fileFor(record), contentDescription = record.title, modifier = Modifier.fillMaxWidth().height(140.dp), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
                                Text(record.title, style = MaterialTheme.typography.titleSmall)
                                Text(
                                    text = record.originalFilename,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                record.awardedAt?.let { millis ->
                                    Text(
                                        text = "获奖时间：" + Instant.ofEpochMilli(millis).atZone(honorZone).toLocalDate().format(honorDateFormatter),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                if (record.note.isNotBlank()) {
                                    Text(record.note, style = MaterialTheme.typography.bodyMedium)
                                }
                                Spacer(Modifier.height(LeafySpacing.micro))
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                                    LeafyTextButton(onClick = {
                                        preview = record
                                    }) {
                                        Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null)
                                        Text("打开", modifier = Modifier.padding(start = LeafySpacing.tiny))
                                    }
                                    LeafyTextButton(onClick = { try { shareCampusFile(context, viewModel.fileFor(record), record.contentType) } catch (failure: Exception) { viewModel.reportError(failure.message ?: "分享失败") } }) { Text("分享原文件") }
                                    LeafyTextButton(onClick = { editing = record }) {
                                        Icon(Icons.Outlined.Edit, contentDescription = null)
                                        Text("编辑", modifier = Modifier.padding(start = LeafySpacing.tiny))
                                    }
                                    LeafyTextButton(onClick = { pendingDelete = record }) {
                                        Icon(Icons.Outlined.Delete, contentDescription = null)
                                        Text("删除", modifier = Modifier.padding(start = LeafySpacing.tiny))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    preview?.let { record -> CampusFilePreview(viewModel.fileFor(record), record.contentType) { preview = null } }
    editing?.let { record ->
        HonorRecordEditor(
            record = record,
            saving = saving, error = message,
            onDismiss = { editing = null },
            onSave = { title, note, awardedAt ->
                viewModel.update(record, title, note, awardedAt) { editing = null }
            },
        )
    }
    pendingDelete?.let { record ->
        LeafyAlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("删除荣誉记录") },
            text = { Text("将同时删除本机保存的文件，且无法恢复。") },
            confirmButton = {
                LeafyTextButton(onClick = {
                    pendingDelete = null
                    viewModel.delete(record)
                }) { Text("删除") }
            },
            dismissButton = { LeafyTextButton(onClick = { pendingDelete = null }) { Text("取消") } },
        )
    }
    Unit
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun HonorRecordEditor(
    record: HonorRecordEntity,
    saving: Boolean, error: String?,
    onDismiss: () -> Unit,
    onSave: (String, String, Long?) -> Unit,
) {
    val context = LocalContext.current
    var title by rememberSaveable(record.id) { mutableStateOf(record.title) }
    var note by rememberSaveable(record.id) { mutableStateOf(record.note) }
    var awardedAt by rememberSaveable(record.id) { mutableStateOf(record.awardedAt) }
    val dirty = title != record.title || note != record.note || awardedAt != record.awardedAt
    val requestExit = rememberEditorExit(dirty, saving, onDismiss)
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = {
        if (it == SheetValue.Hidden && dirty) { requestExit(); false } else true
    })
    LeafyModalBottomSheet(onDismissRequest = requestExit, sheetState = sheetState) {
        LeafySheetContent(
            modifier = Modifier.verticalScroll(rememberScrollState()),
            titleContent = { Text("编辑荣誉记录", style = MaterialTheme.typography.headlineSmall) },
        ) {
            LeafyTextField(
                value = title,
                onValueChange = { title = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("名称") },
                singleLine = true,
            )
            LeafyTextField(
                value = note,
                onValueChange = { note = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("备注") },
                minLines = 2,
                maxLines = 4,
            )
            val current = awardedAt?.let { Instant.ofEpochMilli(it).atZone(honorZone).toLocalDate() }
            LeafyTextButton(onClick = {
                val base = current ?: LocalDate.now()
                DatePickerDialog(
                    context,
                    { _, year, month, day -> awardedAt = LocalDate.of(year, month + 1, day).atStartOfDay(honorZone).toInstant().toEpochMilli() },
                    base.year,
                    base.monthValue - 1,
                    base.dayOfMonth,
                ).show()
            }) {
                Text(current?.let { "获奖时间：${it.format(honorDateFormatter)}" } ?: "选择获奖时间")
            }
            error?.let { LeafyStatusBanner(it, isError = true) }
            LeafyPrimaryButton(onClick = { onSave(title, note, awardedAt) }, enabled = title.isNotBlank() && !saving, modifier = Modifier.fillMaxWidth()) {
                Text(if (saving) "保存中" else "保存")
            }
        }
    }
}

private val honorDateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
