package com.myleafy.android.features.timetable.presentation

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule

internal fun courseTimeDescription(course: CourseEntity): String {
    val weekday = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
        .getOrNull(course.dayOfWeek - 1) ?: "星期未提供"
    val times = course.duration.distinct().sorted().mapNotNull(TimetablePeriodSchedule::slot)
        .joinToString("、") { "${it.startText}–${it.endText}" }
    return if (times.isBlank()) weekday else "$weekday · $times"
}

@Composable
fun ExamDetailsDialog(exam: ExamEntity, onDismiss: () -> Unit) {
    LeafyAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(exam.name) },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
            ) {
                DetailLine("日期", exam.date)
                DetailLine("时间", "${exam.start}–${exam.end}")
                DetailLine("地点", exam.location.ifBlank { "未提供" })
            }
        },
        confirmButton = { LeafyTextButton(onClick = onDismiss) { Text("完成") } },
    )
}

@Composable
private fun DetailLine(label: String, value: String) {
    Text(text = label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
    Text(
        text = value,
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.padding(bottom = com.myleafy.android.ui.theme.LeafySpacing.micro),
    )
}
