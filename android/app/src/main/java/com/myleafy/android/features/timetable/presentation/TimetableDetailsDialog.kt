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

@Composable
fun CourseDetailsDialog(course: CourseEntity, onDismiss: () -> Unit) {
    // 顺序固定为 名称 → 时间地点 → 教师及其他 → 操作：
    // 网格里被省略的地点先出现，教师与班级等只在这里补充。
    LeafyAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(course.courseName) },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
            ) {
                DetailLine("时间", courseTimeDescription(course))
                DetailLine(
                    "节次",
                    course.duration.sorted().joinToString("、") { "第${it}节" }.ifBlank { "未提供" },
                )
                DetailLine(
                    "周次",
                    course.weeks.sorted().joinToString("、") { "第${it}周" }.ifBlank { "未提供" },
                )
                DetailLine("地点", listOf(course.location, course.room).filter(String::isNotBlank).joinToString(" ").ifBlank { "未提供" })
                HorizontalDivider(modifier = Modifier.padding(vertical = com.myleafy.android.ui.theme.LeafySpacing.micro))
                DetailLine("教师", course.teacher.ifBlank { "未提供" })
                DetailLine("班级", course.classInfo.ifBlank { "未提供" })
            }
        },
        confirmButton = { LeafyTextButton(onClick = onDismiss) { Text("完成") } },
    )
}

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
