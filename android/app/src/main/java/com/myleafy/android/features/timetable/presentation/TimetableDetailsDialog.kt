package com.myleafy.android.features.timetable.presentation

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.core.data.local.ExamEntity

@Composable
fun CourseDetailsDialog(course: CourseEntity, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(course.courseName) },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                DetailLine("教师", course.teacher.ifBlank { "未提供" })
                DetailLine("班级", course.classInfo.ifBlank { "未提供" })
                DetailLine("地点", listOf(course.location, course.room).filter(String::isNotBlank).joinToString(" ").ifBlank { "未提供" })
                HorizontalDivider(modifier = Modifier.padding(vertical = com.myleafy.android.ui.theme.LeafySpacing.micro))
                DetailLine("周次", course.weeks.sorted().joinToString("、") { "第${it}周" })
                DetailLine("节次", course.duration.sorted().joinToString("、") { "第${it}节" })
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("完成") } },
    )
}

@Composable
fun ExamDetailsDialog(exam: ExamEntity, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(exam.name) },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                DetailLine("日期", exam.date)
                DetailLine("时间", "${exam.start}–${exam.end}")
                DetailLine("地点", exam.location.ifBlank { "未提供" })
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("完成") } },
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
