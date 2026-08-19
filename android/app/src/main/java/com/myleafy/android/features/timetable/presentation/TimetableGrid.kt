package com.myleafy.android.features.timetable.presentation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import com.myleafy.android.features.timetable.domain.TimetableWeekProjection
import com.myleafy.android.features.timetable.domain.WeekCourseCell

private val PeriodAxisWidth = 40.dp
private val RowHeight = 56.dp

/**
 * 课程卡片调色板：由主题鼠尾草绿衍生的柔和色阶（对应 iOS courseCardColors）。
 */
private val coursePalette = listOf(
    Color(0xFF9DC183),
    Color(0xFFA9C88C),
    Color(0xFFB3CE98),
    Color(0xFF8FB2A0),
    Color(0xFF9CC0AA),
    Color(0xFF86B2B0),
    Color(0xFF96BBC2),
)

/** 稳定课程颜色索引（对应 iOS `stableCourseColorIndex`，31 进制滚动哈希）。 */
fun stableCourseColorIndex(name: String, colorCount: Int): Int {
    if (name.isEmpty() || colorCount <= 0) return 0
    var hash: UInt = 0u
    for (char in name) {
        hash = hash * 31u + char.code.toUInt()
    }
    return (hash % colorCount.toUInt()).toInt()
}

@Composable
fun WeekSelector(
    week: Int,
    totalWeeks: Int,
    onWeekSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyRow(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items((1..totalWeeks).toList()) { candidateWeek ->
            FilterChip(
                selected = candidateWeek == week,
                onClick = { onWeekSelected(candidateWeek) },
                label = { Text("第 $candidateWeek 周") },
            )
        }
    }
}

@Composable
fun TimetableGrid(
    courses: List<CourseEntity>,
    week: Int,
    modifier: Modifier = Modifier,
) {
    val projection = remember(courses, week) {
        TimetableWeekProjection.projectWeek(courses, week)
    }

    Column(modifier = modifier) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Spacer(modifier = Modifier.width(PeriodAxisWidth))
            TimetableWeekProjection.dayLabels.forEach { label ->
                Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        Spacer(modifier = Modifier.height(4.dp))

        LazyColumn {
            items(13) { periodIndex ->
                val period = periodIndex + 1
                Row(modifier = Modifier.height(RowHeight)) {
                    Box(modifier = Modifier.width(PeriodAxisWidth), contentAlignment = Alignment.Center) {
                        Text(
                            text = TimetablePeriodSchedule.slot(period)?.startText ?: "",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.outline,
                        )
                    }
                    for (day in 1..7) {
                        val cell = projection[day]?.firstOrNull { it.startPeriod == period }
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .padding(1.dp),
                        ) {
                            if (cell != null) {
                                CourseCell(cell = cell)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CourseCell(cell: WeekCourseCell) {
    val background = remember(cell.course.courseName) {
        coursePalette[stableCourseColorIndex(cell.course.courseName, coursePalette.size)].copy(alpha = 0.85f)
    }
    Box(
        modifier = Modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(6.dp))
            .background(background)
            .padding(4.dp),
    ) {
        Column {
            Text(
                text = cell.course.courseName,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (cell.course.location.isNotEmpty() || cell.course.room.isNotEmpty()) {
                Text(
                    text = "${cell.course.location} ${cell.course.room}".trim(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.8f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Start,
                )
            }
        }
    }
}
