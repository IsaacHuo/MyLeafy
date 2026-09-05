package com.myleafy.android.features.profile

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.features.timetable.background.TimetableBackgroundRepository
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryButton
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafySpacing
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class TimetableBackgroundViewModel(private val repository: TimetableBackgroundRepository) : ViewModel() {
    val settings: StateFlow<TimetableBackgroundSettings> = repository.settings.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        TimetableBackgroundSettings(),
    )
    private val mutableError = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = mutableError

    fun update(transform: (TimetableBackgroundSettings) -> TimetableBackgroundSettings) {
        viewModelScope.launch {
            runCatching { repository.update(transform(settings.value)) }
                .onFailure { mutableError.value = it.message ?: "背景设置保存失败" }
        }
    }

    fun importPhoto(uri: Uri) {
        viewModelScope.launch {
            runCatching { repository.importPhoto(uri, settings.value) }
                .onFailure { mutableError.value = it.message ?: "照片导入失败" }
        }
    }

    fun removePhoto() {
        viewModelScope.launch {
            runCatching { repository.removePhoto(settings.value) }
                .onFailure { mutableError.value = it.message ?: "照片移除失败" }
        }
    }
}

@Composable
fun TimetableBackgroundScreen(
    onBack: () -> Unit,
    viewModel: TimetableBackgroundViewModel = viewModel(
        factory = appViewModelFactory { TimetableBackgroundViewModel(it.timetableBackgroundRepository) },
    ),
) {
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) {
        it?.let(viewModel::importPhoto)
    }
    LeafySecondaryScaffold(title = "课表背景", onBack = onBack) { contentModifier ->
        Column(
            modifier = contentModifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            error?.let { LeafyStatusBanner(it, isError = true) }
            LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(LeafySpacing.card),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("启用课表背景", style = MaterialTheme.typography.titleSmall)
                        Text("关闭后保留照片和参数", style = MaterialTheme.typography.bodySmall)
                    }
                    Switch(settings.enabled, { enabled -> viewModel.update { it.copy(enabled = enabled) } })
                }
            }
            LeafySectionHeader("背景来源")
            Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                FilterChip(settings.kind == "color", { viewModel.update { it.copy(kind = "color", enabled = true) } }, { Text("纯色") })
                FilterChip(settings.kind == "photo", { viewModel.update { it.copy(kind = "photo", enabled = true) } }, { Text("照片") })
            }
            if (settings.kind == "photo") {
                Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                    LeafyPrimaryButton(onClick = {
                        photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }) { Text(if (settings.photoPath == null) "选择照片" else "替换照片") }
                    if (settings.photoPath != null) LeafySecondaryButton(onClick = viewModel::removePhoto) { Text("移除") }
                }
                Text("使用 Android Photo Picker，不申请媒体库读取权限。", style = MaterialTheme.typography.bodySmall)
            } else {
                ColorSettings(settings, viewModel)
            }
            LeafySectionHeader("显示方式")
            Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                FilterChip(settings.contentScale == "crop", { viewModel.update { it.copy(contentScale = "crop") } }, { Text("铺满") })
                FilterChip(settings.contentScale == "fit", { viewModel.update { it.copy(contentScale = "fit") } }, { Text("完整显示") })
            }
            BackgroundSlider("背景可见度", settings.visibilityPercent, 0..100) { value -> viewModel.update { it.copy(visibilityPercent = value) } }
            BackgroundSlider("模糊", settings.blurRadius, 0..25) { value -> viewModel.update { it.copy(blurRadius = value) } }
            BackgroundSlider("遮罩", settings.overlayPercent, 0..100) { value -> viewModel.update { it.copy(overlayPercent = value) } }
            BackgroundSlider("课程块不透明度", settings.courseOpacityPercent, 35..100) { value -> viewModel.update { it.copy(courseOpacityPercent = value) } }
            LeafyStatusBanner("背景只影响本机课表显示，不会进入 ICS、共享课表快照或系统分享内容。", isError = false)
        }
    }
}

@Composable
private fun ColorSettings(settings: TimetableBackgroundSettings, viewModel: TimetableBackgroundViewModel) {
    val presets = listOf("#DDE9DF", "#E9E3D5", "#DDE7F0", "#EFE1E7", "#DADFE3")
    var hex by remember(settings.colorHex) { mutableStateOf(settings.colorHex) }
    Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
        presets.forEach { value ->
            Box(
                modifier = Modifier
                    .background(parseColor(value), CircleShape)
                    .clickable { viewModel.update { it.copy(colorHex = value, enabled = true, kind = "color") } }
                    .padding(LeafySpacing.card),
            )
        }
    }
    OutlinedTextField(
        value = hex,
        onValueChange = { hex = it },
        label = { Text("十六进制颜色") },
        supportingText = { Text("例如 #DDE9DF") },
        trailingIcon = {
            LeafyTextButton(enabled = isValidHex(hex), onClick = { viewModel.update { it.copy(colorHex = normalizedHex(hex), enabled = true, kind = "color") } }) {
                Text("应用")
            }
        },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun BackgroundSlider(label: String, value: Int, range: IntRange, onValueChangeFinished: (Int) -> Unit) {
    var local by remember(value) { mutableStateOf(value.toFloat()) }
    Column {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label)
            Text(local.toInt().toString(), style = MaterialTheme.typography.bodySmall)
        }
        Slider(
            value = local,
            onValueChange = { local = it },
            onValueChangeFinished = { onValueChangeFinished(local.toInt()) },
            valueRange = range.first.toFloat()..range.last.toFloat(),
        )
    }
}

private fun isValidHex(value: String) = value.trim().matches(Regex("^#?[0-9A-Fa-f]{6}$"))
private fun normalizedHex(value: String) = "#" + value.trim().removePrefix("#").uppercase()
private fun parseColor(value: String): Color = runCatching { Color(android.graphics.Color.parseColor(value)) }.getOrDefault(Color.Gray)
