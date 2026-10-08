package com.myleafy.android.features.timetable.presentation

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.myleafy.android.ui.theme.LeafySpacing
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Composable
internal fun TimetableWeekHeader(week: Int, currentWeek: Int, startDate: LocalDate, onChoose: () -> Unit, modifier: Modifier = Modifier) {
    val label = if (week == currentWeek) "本周 · 第 $week 周" else "第 $week 周"
    val formatter = DateTimeFormatter.ofPattern("M.d")
    val range = "${startDate.format(formatter)} – ${startDate.plusDays(6).format(formatter)}"
    BoxWithConstraints(modifier.fillMaxWidth().padding(horizontal = LeafySpacing.tiny)) {
        val density = LocalDensity.current
        val measurer = rememberTextMeasurer()
        val textWidth = measurer.measure(label, MaterialTheme.typography.titleMedium).size.width +
            measurer.measure(range, MaterialTheme.typography.labelMedium).size.width
        val stacked = with(density) { textWidth.toDp() } + 18.dp + LeafySpacing.compact > maxWidth
        val choose: @Composable () -> Unit = {
            Surface(onClick = onChoose, color = Color.Transparent,
                modifier = Modifier.heightIn(min = 48.dp)
                    .testTag("timetable-week").semantics { contentDescription = "$label，选择周次" }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(LeafySpacing.tiny)) {
                    Text(label, style = MaterialTheme.typography.titleMedium)
                    Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (stacked) {
            Column(Modifier.fillMaxWidth().padding(bottom = LeafySpacing.tiny)) {
                choose()
                Text(range, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                choose()
                Text(range, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
