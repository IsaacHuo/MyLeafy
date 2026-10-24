package com.myleafy.android.features.timetable

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.core.prefs.Settings
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import com.myleafy.android.features.timetable.domain.TimetableUserSettings
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.components.rememberEditorExit
import com.myleafy.android.ui.theme.LeafySpacing
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter

private val settingsDateFormatter = DateTimeFormatter.ofPattern("yyyy年M月d日")

/**
 * 课表时间设置：学期标签、第一周星期一、每天节次与每节作息。
 * 固定 20 周；学期标签和开学日期只影响显示/周次，不改变已拉取课程的存储学期。
 */
@Composable
fun TimetableSettingsScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val container = (context.applicationContext as MyLeafyApplication).container
    val settings by container.settingsStore.settings.collectAsStateWithLifecycle(initialValue = Settings())
    var draft by remember { mutableStateOf(settings.timetableSettings) }
    var initialized by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(settings.timetableSettings) {
        if (!initialized) {
            draft = settings.timetableSettings
            initialized = true
        }
    }
    val dirty = initialized && draft != settings.timetableSettings
    val requestExit = rememberEditorExit(dirty, saving, onBack)

    fun showDatePicker() {
        val current = draft.firstMonday
        DatePickerDialog(
            context,
            { _, year, month, day ->
                draft = draft.copy(
                    firstMonday = TimetableUserSettings.mondayOf(LocalDate.of(year, month + 1, day)),
                )
            },
            current.year,
            current.monthValue - 1,
            current.dayOfMonth,
        ).show()
    }

    fun showTimePicker(index: Int, end: Boolean) {
        val slot = draft.periods.getOrNull(index) ?: return
        TimePickerDialog(
            context,
            { _, hour, minute ->
                val periods = draft.periods.toMutableList()
                val old = periods[index]
                periods[index] = if (end) {
                    old.copy(endHour = hour, endMinute = minute)
                } else {
                    old.copy(startHour = hour, startMinute = minute)
                }
                draft = draft.copy(periods = periods)
            },
            if (end) slot.endHour else slot.startHour,
            if (end) slot.endMinute else slot.startMinute,
            true,
        ).show()
    }

    fun save() {
        val normalized = draft.copy(firstMonday = TimetableUserSettings.mondayOf(draft.firstMonday))
        val validation = normalized.validationError
        if (validation != null) {
            error = validation
            return
        }
        error = null
        saving = true
        scope.launch {
            try {
                container.settingsStore.setTimetableSettings(normalized)
                SemesterConfig.applyUserSettings(normalized)
                onBack()
            } catch (failure: Exception) {
                error = failure.message ?: "保存课表设置失败"
            } finally {
                saving = false
            }
        }
    }

    LeafySecondaryScaffold(title = "课表设置", onBack = requestExit, modifier = modifier) { contentModifier ->
        LazyColumn(
            modifier = contentModifier.fillMaxSize().testTag("timetable-settings"),
            contentPadding = PaddingValues(horizontal = LeafySpacing.page, vertical = LeafySpacing.compact),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                SettingsSection(title = "学期与开学日期") {
                    StepperRow(
                        label = "学年",
                        value = "${draft.academicYear}–${draft.academicYear + 1}",
                        onMinus = { draft = draft.copy(academicYear = (draft.academicYear - 1).coerceAtLeast(1900)) },
                        onPlus = { draft = draft.copy(academicYear = (draft.academicYear + 1).coerceAtMost(2200)) },
                    )
                    Spacer(Modifier.height(LeafySpacing.compact))
                    Text("学期", style = MaterialTheme.typography.titleSmall)
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        listOf(1 to "第一学期", 2 to "第二学期").forEachIndexed { index, (value, label) ->
                            SegmentedButton(
                                selected = draft.term == value,
                                onClick = { draft = draft.copy(term = value) },
                                shape = SegmentedButtonDefaults.itemShape(index, 2),
                            ) { Text(label) }
                        }
                    }
                    Spacer(Modifier.height(LeafySpacing.compact))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("第一周的星期一", style = MaterialTheme.typography.titleSmall)
                            Text(
                                text = "${draft.firstMonday.format(settingsDateFormatter)}（周一）",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        LeafyTextButton(onClick = ::showDatePicker) { Text("更改") }
                    }
                    Spacer(Modifier.height(LeafySpacing.micro))
                    Text(
                        text = "固定 20 周。学年和学期用于显示，开学日期决定第 1 周和后续周次；不会改变已拉取的课表。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item {
                SettingsSection(title = "节次与作息") {
                    StepperRow(
                        label = "每天节次",
                        value = "${draft.periods.size} 节",
                        onMinus = { draft = draft.withPeriodCount(draft.periods.size - 1) },
                        onPlus = { draft = draft.withPeriodCount(draft.periods.size + 1) },
                    )
                    Spacer(Modifier.height(LeafySpacing.micro))
                    Text(
                        text = "开始时间须早于结束时间，各节不能重叠。新增节次后请核对作息。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            itemsIndexed(draft.periods, key = { _, slot -> slot.period }) { index, slot ->
                PeriodRow(
                    index = index,
                    slot = slot,
                    onStartClick = { showTimePicker(index, end = false) },
                    onEndClick = { showTimePicker(index, end = true) },
                )
            }
            error?.let { message ->
                item { LeafyStatusBanner(message = message, isError = true, onDismiss = { error = null }) }
            }
            item {
                LeafyPrimaryButton(
                    onClick = ::save,
                    enabled = !saving && draft.isValid,
                    modifier = Modifier.fillMaxWidth().testTag("timetable-settings-save"),
                ) {
                    Text(if (saving) "保存中…" else "保存课表设置")
                }
                Spacer(Modifier.height(LeafySpacing.compact))
            }
        }
    }
}

@Composable
private fun SettingsSection(title: String, content: @Composable () -> Unit) {
    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(LeafySpacing.card)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(LeafySpacing.compact))
            content()
        }
    }
}

@Composable
private fun StepperRow(
    label: String,
    value: String,
    onMinus: () -> Unit,
    onPlus: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
        LeafyTextButton(onClick = onMinus) { Text("−", textAlign = TextAlign.Center) }
        Text(value, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.width(104.dp), textAlign = TextAlign.Center)
        LeafyTextButton(onClick = onPlus) { Text("+", textAlign = TextAlign.Center) }
    }
}

@Composable
private fun PeriodRow(
    index: Int,
    slot: TimetablePeriodSchedule.Slot,
    onStartClick: () -> Unit,
    onEndClick: () -> Unit,
) {
    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = LeafySpacing.card, vertical = LeafySpacing.micro),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
        ) {
            Text("第 ${index + 1} 节", style = MaterialTheme.typography.titleSmall, modifier = Modifier.width(64.dp))
            OutlinedButton(
                onClick = onStartClick,
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
                modifier = Modifier.heightIn(min = 40.dp),
            ) { Text(slot.startText) }
            Text("–", color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(
                onClick = onEndClick,
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
                modifier = Modifier.heightIn(min = 40.dp),
            ) { Text(slot.endText) }
        }
    }
}
