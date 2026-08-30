package com.myleafy.android.features.timetable.presentation

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.myleafy.android.features.timetable.domain.TimetableGridItem
import com.myleafy.android.features.timetable.domain.TimetableGridItemType
import com.myleafy.android.features.timetable.domain.TimetableGridSnapshot
import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

private val AxisWidth = 44.dp
private val MinimumDayWidth = 46.dp
private val HeaderHeight = 40.dp
private val PeriodRowHeight = 48.dp
private val GridGap = 1.dp

private val coursePalette = listOf(
    Color(0xFF5F8F4F),
    Color(0xFF6B9360),
    Color(0xFF568C73),
    Color(0xFF4F8987),
    Color(0xFF527F92),
    Color(0xFF6D7FA0),
    Color(0xFF7C7299),
)

fun stableCourseColorIndex(name: String, colorCount: Int): Int {
    if (name.isEmpty() || colorCount <= 0) return 0
    var hash: UInt = 0u
    for (char in name) hash = hash * 31u + char.code.toUInt()
    return (hash % colorCount.toUInt()).toInt()
}

@Composable
fun TimetableGrid(
    snapshot: TimetableGridSnapshot,
    onEmptyCellClick: (date: LocalDate, period: Int) -> Unit,
    onItemClick: (TimetableGridItem) -> Unit,
    modifier: Modifier = Modifier,
    today: LocalDate = LocalDate.now(),
    currentTime: LocalTime = LocalTime.now(),
) {
    val horizontalScroll = rememberScrollState()
    val verticalScroll = rememberScrollState()
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val minimumWidth = AxisWidth + MinimumDayWidth * 7
        val contentWidth = maxOf(maxWidth, minimumWidth)
        val contentHeight = HeaderHeight + PeriodRowHeight * 13
        Box(
            modifier = Modifier
                .fillMaxSize()
                .horizontalScroll(horizontalScroll)
                .verticalScroll(verticalScroll),
            contentAlignment = Alignment.TopCenter,
        ) {
            TimetableGridLayout(
                snapshot = snapshot,
                today = today,
                currentTime = currentTime,
                onEmptyCellClick = onEmptyCellClick,
                onItemClick = onItemClick,
                modifier = Modifier.width(contentWidth).height(contentHeight),
            )
        }
    }
}

@Composable
private fun TimetableGridLayout(
    snapshot: TimetableGridSnapshot,
    today: LocalDate,
    currentTime: LocalTime,
    onEmptyCellClick: (LocalDate, Int) -> Unit,
    onItemClick: (TimetableGridItem) -> Unit,
    modifier: Modifier,
) {
    val todayIndex = remember(snapshot.weekRange, today) {
        (0..6).firstOrNull { snapshot.weekRange.startDate.plusDays(it.toLong()) == today }
    }
    val timeline = remember(snapshot.weekRange, today, currentTime) {
        todayIndex?.let { day -> currentTimeline(day, currentTime) }
    }

    Layout(
        modifier = modifier,
        content = {
            for (day in 0..6) {
                val date = snapshot.weekRange.startDate.plusDays(day.toLong())
                DayHeader(
                    date = date,
                    isToday = day == todayIndex,
                    modifier = Modifier.layoutId(GridSlot.Header(day)),
                )
            }
            for (period in 1..13) {
                PeriodAxis(
                    period = period,
                    modifier = Modifier.layoutId(GridSlot.Axis(period)),
                )
                for (day in 0..6) {
                    val date = snapshot.weekRange.startDate.plusDays(day.toLong())
                    EmptyGridCell(
                        isToday = day == todayIndex,
                        date = date,
                        period = period,
                        onClick = { onEmptyCellClick(date, period) },
                        modifier = Modifier.layoutId(GridSlot.Cell(day, period)),
                    )
                }
            }
            snapshot.items.forEach { item ->
                TimetableItemCard(
                    item = item,
                    onClick = { onItemClick(item) },
                    modifier = Modifier
                        .layoutId(GridSlot.Item(item))
                        .zIndex(1f),
                )
            }
            if (timeline != null) {
                Box(
                    modifier = Modifier
                        .layoutId(GridSlot.Timeline(timeline.day, timeline.rowPosition))
                        .zIndex(2f)
                        .height(2.dp)
                        .background(MaterialTheme.colorScheme.error),
                )
            }
        },
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val axisWidth = AxisWidth.roundToPx()
        val headerHeight = HeaderHeight.roundToPx()
        val rowHeight = PeriodRowHeight.roundToPx()
        val gap = GridGap.roundToPx()
        val dayWidth = (width - axisWidth) / 7f

        val placements = measurables.map { measurable ->
            val slot = measurable.layoutId as GridSlot
            val childConstraints = when (slot) {
                is GridSlot.Header -> Constraints.fixed(dayWidth.roundToInt(), headerHeight)
                is GridSlot.Axis -> Constraints.fixed(axisWidth, rowHeight)
                is GridSlot.Cell -> Constraints.fixed(
                    (dayWidth.roundToInt() - gap * 2).coerceAtLeast(1),
                    (rowHeight - gap * 2).coerceAtLeast(1),
                )
                is GridSlot.Item -> {
                    val laneWidth = dayWidth / slot.item.laneCount
                    Constraints.fixed(
                        (laneWidth.roundToInt() - gap * 2).coerceAtLeast(1),
                        (rowHeight * slot.item.periodSpan - gap * 2).coerceAtLeast(1),
                    )
                }
                is GridSlot.Timeline -> Constraints.fixed(
                    (dayWidth.roundToInt() - gap * 2).coerceAtLeast(1),
                    2.dp.roundToPx(),
                )
            }
            slot to measurable.measure(childConstraints)
        }

        layout(width, height) {
            placements.forEach { (slot, placeable) ->
                val x: Int
                val y: Int
                when (slot) {
                    is GridSlot.Header -> {
                        x = axisWidth + (slot.day * dayWidth).roundToInt()
                        y = 0
                    }
                    is GridSlot.Axis -> {
                        x = 0
                        y = headerHeight + (slot.period - 1) * rowHeight
                    }
                    is GridSlot.Cell -> {
                        x = axisWidth + (slot.day * dayWidth).roundToInt() + gap
                        y = headerHeight + (slot.period - 1) * rowHeight + gap
                    }
                    is GridSlot.Item -> {
                        val laneWidth = dayWidth / slot.item.laneCount
                        x = axisWidth + (slot.item.dayIndex * dayWidth).roundToInt() +
                            (slot.item.lane * laneWidth).roundToInt() + gap
                        y = headerHeight + (slot.item.startPeriod - 1) * rowHeight + gap
                    }
                    is GridSlot.Timeline -> {
                        x = axisWidth + (slot.day * dayWidth).roundToInt() + gap
                        y = headerHeight + (slot.rowPosition * rowHeight).roundToInt()
                    }
                }
                placeable.placeRelative(x, y)
            }
        }
    }
}

@Composable
private fun DayHeader(date: LocalDate, isToday: Boolean, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.padding(2.dp),
        shape = MaterialTheme.shapes.small,
        color = if (isToday) MaterialTheme.colorScheme.primaryContainer else Color.Transparent,
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = dayLabels[date.dayOfWeek.value - 1],
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(top = 2.dp),
            )
            Text(
                text = date.format(DateTimeFormatter.ofPattern("M/d")),
                style = MaterialTheme.typography.labelSmall,
                color = if (isToday) {
                    MaterialTheme.colorScheme.onPrimaryContainer
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        }
    }
}

@Composable
private fun PeriodAxis(period: Int, modifier: Modifier = Modifier) {
    val slot = TimetablePeriodSchedule.slot(period)
    Column(
        modifier = modifier.padding(top = 3.dp, end = 4.dp),
        horizontalAlignment = Alignment.End,
    ) {
        Text(text = period.toString(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
        Text(
            text = slot?.startText.orEmpty(),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.outline,
        )
    }
}

@Composable
private fun EmptyGridCell(
    isToday: Boolean,
    date: LocalDate,
    period: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        onClick = onClick,
        modifier = modifier.testTag("timetable-cell-${date}-$period").semantics {
            contentDescription = "${date.monthValue}月${date.dayOfMonth}日 第${period}节，添加日程"
        },
        shape = MaterialTheme.shapes.small,
        color = if (isToday) {
            MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.18f)
        } else {
            MaterialTheme.colorScheme.surfaceContainerLowest
        },
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f)),
    ) {}
}

@Composable
private fun TimetableItemCard(
    item: TimetableGridItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val containerColor = when (item.type) {
        TimetableGridItemType.COURSE -> coursePalette[
            stableCourseColorIndex(item.title, coursePalette.size)
        ]
        TimetableGridItemType.EXAM -> MaterialTheme.colorScheme.tertiary
        TimetableGridItemType.SCHEDULE -> MaterialTheme.colorScheme.secondary
    }
    Surface(
        onClick = onClick,
        modifier = modifier.testTag("timetable-item-${item.stableId}").semantics(mergeDescendants = true) {
            contentDescription = "${item.title}，第${item.startPeriod}至${item.endPeriod}节"
        },
        shape = MaterialTheme.shapes.small,
        color = containerColor,
        contentColor = Color.White,
        shadowElevation = 1.dp,
    ) {
        Column(modifier = Modifier.fillMaxSize().padding(3.dp)) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = if (item.periodSpan > 1) 3 else 2,
                overflow = TextOverflow.Ellipsis,
            )
            item.subtitle?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.85f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

private fun currentTimeline(day: Int, time: LocalTime): CurrentTimeline? {
    val minutes = time.hour * 60 + time.minute
    val slot = TimetablePeriodSchedule.periodForFocus(minutes) ?: return null
    if (minutes < TimetablePeriodSchedule.slots.first().startMinutes ||
        minutes > TimetablePeriodSchedule.slots.last().endMinutes
    ) return null
    val fraction = ((minutes - slot.startMinutes).toFloat() / (slot.endMinutes - slot.startMinutes))
        .coerceIn(0f, 1f)
    return CurrentTimeline(day = day, rowPosition = (slot.period - 1) + fraction)
}

private data class CurrentTimeline(val day: Int, val rowPosition: Float)

private sealed interface GridSlot {
    data class Header(val day: Int) : GridSlot
    data class Axis(val period: Int) : GridSlot
    data class Cell(val day: Int, val period: Int) : GridSlot
    data class Item(val item: TimetableGridItem) : GridSlot
    data class Timeline(val day: Int, val rowPosition: Float) : GridSlot
}

private val dayLabels = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
