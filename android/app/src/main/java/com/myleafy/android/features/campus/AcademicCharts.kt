package com.myleafy.android.features.campus

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.myleafy.android.ui.theme.LeafySpacing

@Composable internal fun AcademicLineChart(values: List<Pair<String, Double>>, lowerIsBetter: Boolean = false) {
    if (values.isEmpty()) { Text("暂无有效周期数据", style = MaterialTheme.typography.bodySmall); return }
    if (values.size == 1) {
        Text("${values.first().first} · ${values.first().second.gradeNumber()}", style = MaterialTheme.typography.bodyMedium)
        Text("至少两个有效周期后显示趋势", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        return
    }
    val color = MaterialTheme.colorScheme.primary
    val guide = MaterialTheme.colorScheme.outlineVariant
    val style = MaterialTheme.typography.bodySmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant)
    val measurer = rememberTextMeasurer()
    val low = values.minOf { it.second }; val high = values.maxOf { it.second }
    val span = (high - low).takeIf { it > 0 }
    val density = LocalDensity.current
    val labels = listOf(high, (high + low) / 2, low).distinct().let { if (lowerIsBetter) it.reversed() else it }
    val labelWidth = with(density) { labels.maxOf { measurer.measure(it.gradeNumber(), style).size.width }.toDp() } + LeafySpacing.compact
    Canvas(Modifier.fillMaxWidth().height(160.dp * density.fontScale.coerceIn(1f, 1.5f)).semantics {
        contentDescription = values.joinToString("；") { "${it.first}：${it.second.gradeNumber()}" }
    }) {
        val left = labelWidth.toPx(); val inset = 12.dp.toPx(); val plotHeight = size.height - inset * 2
        labels.forEachIndexed { index, value ->
            val y = if (labels.size == 1) size.height / 2 else inset + index * plotHeight / (labels.size - 1)
            drawLine(guide, Offset(left, y), Offset(size.width - inset, y), 1.dp.toPx())
            val text = measurer.measure(value.gradeNumber(), style)
            drawText(text, topLeft = Offset(0f, (y - text.size.height / 2).coerceIn(0f, (size.height - text.size.height).coerceAtLeast(0f))))
        }
        val path = Path()
        values.forEachIndexed { index, (_, value) ->
            val ratio = span?.let { ((value - low) / it).toFloat() } ?: .5f
            val point = Offset(left + index * (size.width - left - inset).coerceAtLeast(0f) / (values.size - 1), inset + (if (lowerIsBetter) ratio else 1 - ratio) * plotHeight)
            if (index == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
            drawCircle(color, 3.dp.toPx(), point)
        }
        drawPath(path, color, style = Stroke(2.dp.toPx()))
    }
    Row(Modifier.fillMaxWidth().padding(start = labelWidth), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(values.first().first, Modifier.weight(1f), style = style, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.width(LeafySpacing.compact))
        Text(values.last().first, Modifier.weight(1f), style = style, textAlign = androidx.compose.ui.text.style.TextAlign.End, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable internal fun AcademicBarChart(values: List<Pair<String, Double>>) {
    if (values.isEmpty()) { Text("暂无统计数据", style = MaterialTheme.typography.bodySmall); return }
    val color = MaterialTheme.colorScheme.primary; val guide = MaterialTheme.colorScheme.outlineVariant
    val style = MaterialTheme.typography.bodySmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant)
    val measurer = rememberTextMeasurer(); val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val width = maxOf(maxWidth, 76.dp * density.fontScale.coerceAtLeast(1f) * values.size)
        val scrollable = width > maxWidth
        Column {
            Box(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())) {
                Canvas(Modifier.width(width).height(190.dp * density.fontScale.coerceIn(1f, 1.5f)).semantics {
                    contentDescription = values.joinToString("；") { "${it.first}：${it.second.gradeNumber()}" }
                }) {
                    val segment = size.width / values.size; val maximum = values.maxOf { it.second }.coerceAtLeast(1.0)
                    val labelHeight = measurer.measure("学分\n结构", style).size.height.toFloat()
                    val numberHeight = measurer.measure("0", style).size.height.toFloat()
                    val bottom = size.height - labelHeight - 12.dp.toPx()
                    val plotHeight = (bottom - numberHeight - 12.dp.toPx()).coerceAtLeast(0f)
                    drawLine(guide, Offset(0f, bottom), Offset(size.width, bottom), 1.dp.toPx())
                    values.forEachIndexed { index, (label, value) ->
                        val height = (value.coerceAtLeast(0.0) / maximum).toFloat() * plotHeight; val x = index * segment
                        drawRect(color, Offset(x + segment * .25f, bottom - height), Size(segment * .5f, height))
                        val constraint = Constraints(maxWidth = (segment - 8.dp.toPx()).toInt().coerceAtLeast(1))
                        val number = measurer.measure(value.gradeNumber(), style, maxLines = 1, overflow = TextOverflow.Ellipsis, constraints = constraint)
                        drawText(number, topLeft = Offset(x + (segment - number.size.width) / 2, bottom - height - number.size.height - 4.dp.toPx()))
                        val name = measurer.measure(label, style, maxLines = 2, overflow = TextOverflow.Ellipsis, constraints = constraint)
                        drawText(name, topLeft = Offset(x + (segment - name.size.width) / 2, bottom + 8.dp.toPx()))
                    }
                }
            }
            if (scrollable) Text("左右滑动查看完整图表", style = style, modifier = Modifier.padding(top = LeafySpacing.tiny))
        }
    }
}
