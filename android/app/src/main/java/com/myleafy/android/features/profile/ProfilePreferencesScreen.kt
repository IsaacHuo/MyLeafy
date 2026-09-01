package com.myleafy.android.features.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.core.prefs.Settings
import com.myleafy.android.core.prefs.SettingsStore
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.theme.LeafySpacing
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class ProfilePreferencesViewModel(private val settingsStore: SettingsStore) : ViewModel() {
    val settings: StateFlow<Settings> = settingsStore.settings.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = Settings(),
    )

    fun setThemeMode(value: String) {
        viewModelScope.launch { settingsStore.setThemeMode(value) }
    }

    fun setTextScale(value: String) {
        viewModelScope.launch { settingsStore.setTextScale(value) }
    }
}

@Composable
fun ProfilePreferencesScreen(
    onBack: () -> Unit,
    viewModel: ProfilePreferencesViewModel = viewModel(
        factory = appViewModelFactory { ProfilePreferencesViewModel(it.settingsStore) },
    ),
) {
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    LeafySecondaryScaffold(title = "个性化", onBack = onBack) { contentModifier ->
        Column(
            modifier = contentModifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            LeafySectionHeader("主题", supportingText = "设置会立即应用，并在下次启动时保留。")
            PreferenceCard {
                ChoiceRow(
                    choices = listOf("system" to "跟随系统", "light" to "亮色", "dark" to "深色"),
                    selected = settings.themeMode,
                    onSelect = viewModel::setThemeMode,
                )
            }
            LeafySectionHeader("文字显示", supportingText = "大号文字会在系统字体设置基础上再放大 15%。")
            PreferenceCard {
                ChoiceRow(
                    choices = listOf("system" to "系统大小", "large" to "更大"),
                    selected = settings.textScale,
                    onSelect = viewModel::setTextScale,
                )
                Text(
                    "所有页面仍会尊重 Android 系统字体缩放，包括 1.5 倍字体。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                Text(
                    "课表背景与更复杂的显示密度属于增强阶段，当前不提供无效开关。",
                    modifier = Modifier.padding(LeafySpacing.card),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun PreferenceCard(content: @Composable ColumnScope.() -> Unit) {
    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(LeafySpacing.card),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
            content = content,
        )
    }
}

@Composable
private fun ChoiceRow(
    choices: List<Pair<String, String>>,
    selected: String,
    onSelect: (String) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
    ) {
        choices.forEach { (value, label) ->
            FilterChip(
                selected = selected == value,
                onClick = { onSelect(value) },
                label = { Text(label) },
            )
        }
    }
}
