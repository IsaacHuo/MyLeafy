package com.myleafy.android.features.campus

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp

@Composable internal fun AcademicLineChart(values: List<Pair<String, Double>>, lowerIsBetter: Boolean = false) {
    val color = MaterialTheme.colorScheme.primary
    if (values.size < 2) { Text("至少两个有效周期后显示趋势", style = MaterialTheme.typography.bodySmall); return }
    Canvas(Modifier.fillMaxWidth().height(150.dp).semantics { contentDescription = values.joinToString("；") { "${it.first}：${it.second}" } }) {
        val low = values.minOf { it.second }; val high = values.maxOf { it.second }; val span = (high - low).coerceAtLeast(1.0)
        val path = Path()
        values.forEachIndexed { index, (_, value) ->
            val ratio = ((value - low) / span).toFloat()
            val point = Offset(12.dp.toPx() + index * (size.width - 24.dp.toPx()) / (values.size - 1), 12.dp.toPx() + (if (lowerIsBetter) ratio else 1 - ratio) * (size.height - 24.dp.toPx()))
            if (index == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
            drawCircle(color, 4.dp.toPx(), point)
        }
        drawPath(path, color, style = Stroke(2.dp.toPx()))
    }
    Text("${values.first().first} → ${values.last().first}", style = MaterialTheme.typography.bodySmall)
}

@Composable internal fun AcademicBarChart(values: List<Pair<String, Double>>) {
    val color = MaterialTheme.colorScheme.primary
    Canvas(Modifier.fillMaxWidth().height(140.dp).semantics { contentDescription = values.joinToString("；") { "${it.first}：${it.second}" } }) {
        if (values.isEmpty()) return@Canvas
        val maximum = values.maxOf { it.second }.coerceAtLeast(1.0)
        val segment = size.width / values.size
        values.forEachIndexed { index, (_, value) ->
            val height = (value / maximum).toFloat() * size.height
            drawRect(color, Offset(index * segment + segment * .15f, size.height - height), Size(segment * .7f, height))
        }
    }
    Text(values.joinToString(" · ") { "${it.first} ${it.second.gradeNumber()}" }, style = MaterialTheme.typography.bodySmall)
}
