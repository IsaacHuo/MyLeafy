package com.myleafy.android.features.campus

import com.myleafy.android.ui.components.LeafyLoadingState

import android.content.ClipData
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.automirrored.outlined.DirectionsRun
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.outlined.LocalHospital
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.SportsBasketball
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import com.myleafy.android.ui.components.LeafyTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.myleafy.android.ui.components.rememberEditorExit
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
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.data.local.FitnessTestRecordEntity
import com.myleafy.android.core.data.local.MedicalLedgerEntryEntity
import com.myleafy.android.core.data.local.MedicalLedgerPhotoEntity
import com.myleafy.android.core.data.local.SunshineRunRecordEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.math.ceil

@Composable
internal fun SunshineRulesDialog(
    saving: Boolean, error: String?,
    total: Int,
    periodWeeks: Int,
    periodTarget: Int,
    excludedWeeks: String,
    skipsExcludedWeeks: Boolean,
    onDismiss: () -> Unit,
    onSave: (Int, Int, Int, String, Boolean) -> Unit,
) {
    var totalText by rememberSaveable(total) { mutableStateOf(total.toString()) }
    var weeksText by rememberSaveable(periodWeeks) { mutableStateOf(periodWeeks.toString()) }
    var targetText by rememberSaveable(periodTarget) { mutableStateOf(periodTarget.toString()) }
    var excludedText by rememberSaveable(excludedWeeks) { mutableStateOf(excludedWeeks) }
    var skipExcluded by rememberSaveable { mutableStateOf(skipsExcludedWeeks) }
    val valid = totalText.toIntOrNull()?.let { it in 1..200 } == true && weeksText.toIntOrNull()?.let { it in 1..8 } == true && targetText.toIntOrNull()?.let { it in 1..30 } == true && excludedText.split(',').all { it.isBlank() || it.trim().toIntOrNull()?.let { week -> week in 1..20 } == true }
    val dirty = totalText != total.toString() || weeksText != periodWeeks.toString() || targetText != periodTarget.toString() || excludedText != excludedWeeks || skipExcluded != skipsExcludedWeeks
    val requestExit = rememberEditorExit(dirty, saving, onDismiss)
    LeafyAlertDialog(
        onDismissRequest = requestExit,
        title = { Text("长跑规则") },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
                error?.let { LeafyStatusBanner(it, isError = true) }
                Row { androidx.compose.material3.Switch(skipExcluded, { skipExcluded = it }); Text("跳过排除周") }
                NumberField(totalText, { totalText = it }, "全学期目标次数")
                NumberField(weeksText, { weeksText = it }, "每周期周数")
                NumberField(targetText, { targetText = it }, "每周期目标次数")
                LeafyTextField(
                    value = excludedText,
                    onValueChange = { excludedText = it },
                    label = { Text("排除周（逗号分隔）") },
                    supportingText = { Text("例如：1,8,20") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            LeafyTextButton(enabled = valid && !saving, onClick = {
                onSave(totalText.toInt(), weeksText.toInt(), targetText.toInt(), excludedText, skipExcluded)
            }) { Text(if (saving) "保存中" else "保存") }
        },
        dismissButton = { LeafyTextButton(onClick = requestExit) { Text("取消") } },
    )
}

private enum class MedicalSection(val title: String) { POLICY("政策"), GUIDE("报销指引"), LEDGER("台账") }

@Composable
fun MedicalScreen(
    onBack: () -> Unit,
    embedded: Boolean = false,
    modifier: Modifier = Modifier,
    available: Boolean,
    viewModel: MedicalViewModel = viewModel(factory = appViewModelFactory { MedicalViewModel(it.campusLifeRepository) }),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val saving by viewModel.saving.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var section by rememberSaveable { mutableStateOf(MedicalSection.POLICY) }
    var editorVisible by rememberSaveable { mutableStateOf(false) }
    var editing by remember { mutableStateOf<MedicalLedgerEntryEntity?>(null) }
    var photoEntryId by rememberSaveable { mutableStateOf<String?>(null) }
    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
        val entryId = photoEntryId
        photoEntryId = null
        if (uris.isNotEmpty() && entryId != null) viewModel.importPhotos(entryId, uris)
    }
    LaunchedEffect(state.exportedFile) {
        val file = state.exportedFile ?: return@LaunchedEffect
        runCatching {
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                type = "application/zip"
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri("医疗报销台账", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, "分享医疗台账"))
        }.onFailure { viewModel.reportError(it.message ?: "分享失败") }
        viewModel.consumeExport()
    }
    LeafySecondaryScaffold(
        title = "医疗事项",
        embedded = embedded,
        modifier = modifier,
        onBack = onBack,
        actions = {
            if (available && section == MedicalSection.LEDGER) {
                LeafyActionIconButton(enabled = !state.loading && !state.loadFailed && !saving, onClick = viewModel::export) { Icon(Icons.Outlined.FileUpload, "导出医疗台账") }
                LeafyActionIconButton(enabled = !state.loading && !state.loadFailed && !saving, onClick = { editing = null; editorVisible = true }) { Icon(Icons.Filled.Add, "新增医疗台账") }
            }
        },
    ) { contentModifier ->
        if (!available) {
            Box(modifier = contentModifier, contentAlignment = Alignment.Center) {
                LeafyEmptyState("当前校园暂不支持医疗事项", "该服务目前仅面向北京林业大学。", icon = Icons.Outlined.LocalHospital)
            }
        } else {
            Column(modifier = contentModifier.padding(horizontal = LeafySpacing.page)) {
                error?.let { LeafyStatusBanner(it, isError = true, onDismiss = viewModel::dismissError) }
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    MedicalSection.entries.forEachIndexed { index, item ->
                        SegmentedButton(
                            selected = section == item,
                            onClick = { section = item },
                            shape = SegmentedButtonDefaults.itemShape(index, MedicalSection.entries.size),
                            modifier = Modifier.weight(1f),
                            label = { Text(item.title) },
                        )
                    }
                }
                when (section) {
                    MedicalSection.POLICY -> MedicalPolicyContent(Modifier.weight(1f))
                    MedicalSection.GUIDE -> MedicalGuideContent(Modifier.weight(1f))
                    MedicalSection.LEDGER -> if (state.loading) LeafyLoadingState(Modifier.weight(1f))
                    else if (state.loadFailed) LeafyTextButton(onClick = viewModel::retryLoad) { Text("重新加载医疗台账") }
                    else MedicalLedgerContent(
                        entries = state.entries,
                        photos = state.photos,
                        onDelete = viewModel::delete,
                        onEdit = { editing = it; editorVisible = true },
                        onDeletePhoto = viewModel::deletePhoto,
                        onAddPhoto = { entryId ->
                            photoEntryId = entryId
                            photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
    if (editorVisible) {
        MedicalEditorDialog(
            initial = editing,
            saving = saving, error = error,
            onDismiss = { editorVisible = false },
            onSave = { viewModel.save(it) { editorVisible = false } },
        )
    }
}

@Composable
private fun TextFieldValue(value: String, onValueChange: (String) -> Unit, label: String) {
    LeafyTextField(value, onValueChange, label = { Text(label) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
}

@Composable
private fun NumberField(value: String, onValueChange: (String) -> Unit, label: String) {
    LeafyTextField(value, { onValueChange(it.filter(Char::isDigit)) }, label = { Text(label) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
}

@Composable
internal fun sportsViewModel(): SportsViewModel = viewModel(
    factory = appViewModelFactory { SportsViewModel(it.campusLifeRepository) },
)

private fun parseWeekSet(raw: String): Set<Int> = raw.split(',').mapNotNull { it.trim().toIntOrNull() }.toSet()

private fun weekForDate(date: LocalDate): Int =
    (ChronoUnit.DAYS.between(SemesterConfig.current.semesterStartDate, date) / 7 + 1).toInt()
