package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import java.time.format.DateTimeFormatter

private val calendarDateFormatter = DateTimeFormatter.ofPattern("yyyy年M月d日")

@Composable
fun CampusCalendarScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val configurations = SemesterConfig.timelineConfigurations
    LeafySecondaryScaffold(title = "校历", onBack = onBack, modifier = modifier) { contentModifier ->
        LazyColumn(
            modifier = contentModifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text(
                    text = "学期与重要日期",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "以下内容来自 App 当前内置的学期运行配置；学校发布的新校历仍以官方信息为准。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            configurations.forEach { config ->
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text(
                                text = config.semesterId,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = "${config.semesterStartDate.format(calendarDateFormatter)} 开学 · ${config.supportedWeeks} 个教学周",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            if (config.calendarEvents.isEmpty()) {
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    text = "暂无内置重要日期",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.outline,
                                )
                            } else {
                                config.calendarEvents.forEach { event ->
                                    Spacer(modifier = Modifier.height(10.dp))
                                    Text(text = event.title, style = MaterialTheme.typography.titleSmall)
                                    Text(
                                        text = if (event.startDate == event.endDate) {
                                            event.startDate.format(calendarDateFormatter)
                                        } else {
                                            "${event.startDate.format(calendarDateFormatter)} – ${event.endDate.format(calendarDateFormatter)}"
                                        },
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
