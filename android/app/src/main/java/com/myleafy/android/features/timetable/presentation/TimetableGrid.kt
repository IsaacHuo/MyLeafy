package com.myleafy.android.features.timetable.presentation

import android.graphics.BitmapFactory
import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.features.timetable.domain.TimetableGridItem
import com.myleafy.android.features.timetable.domain.TimetableGridItemType
import com.myleafy.android.features.timetable.domain.TimetableGridSnapshot
import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import com.myleafy.android.ui.theme.LeafyElevation
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafyCourseColors
import com.myleafy.android.ui.theme.leafySurfaces
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// High-density timetable geometry is deliberately local rather than shared UI spacing.
private val AxisWidth = 40.dp
private val HeaderHeight = 44.dp
private val MaximumPeriodRowHeight = 56.dp
private val GridGap = 2.dp
private val GridCellShape = RoundedCornerShape(8.dp)
private const val PeriodCount = 13
// Axis metadata is intentionally denser than general UI typography so all
// thirteen start times remain readable without competing with course titles.
private val AxisTimeFontSize = 9.sp
private val AxisTimeLineHeight = 11.sp

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
    showWeekends: Boolean = true,
    background: TimetableBackgroundSettings = TimetableBackgroundSettings(),
) {
    BoxWithConstraints(modifier = modifier.fillMaxSize().testTag("timetable-grid")) {
        val visibleDayCount = if (showWeekends) 7 else 5
        val contentWidth = maxWidth
        // The timetable is a single viewport: rows compress to the available height
        // instead of turning the whole grid into a vertically scrolling surface.
        val periodRowHeight = ((maxHeight - HeaderHeight).coerceAtLeast(PeriodCount.dp) / PeriodCount)
            .coerceAtMost(MaximumPeriodRowHeight)
        val contentHeight = HeaderHeight + periodRowHeight * PeriodCount
        Box(
            modifier = Modifier
                .fillMaxSize(),
            contentAlignment = Alignment.TopCenter,
        ) {
            TimetableBackground(background, Modifier.fillMaxSize())
            TimetableGridLayout(
                snapshot = snapshot,
                today = today,
                currentTime = currentTime,
                onEmptyCellClick = onEmptyCellClick,
                onItemClick = onItemClick,
                headerHeight = HeaderHeight,
                periodRowHeight = periodRowHeight,
                visibleDayCount = visibleDayCount,
                background = background,
                modifier = Modifier.width(contentWidth).height(contentHeight),
            )
        }
    }
}

@Composable
private fun TimetableBackground(settings: TimetableBackgroundSettings, modifier: Modifier = Modifier) {
    if (!settings.enabled) return
    val pageColor = MaterialTheme.leafySurfaces.page
    Box(modifier = modifier) {
        if (settings.kind == "color") {
            Box(
                modifier = Modifier.fillMaxSize().background(
                    parseBackgroundColor(settings.colorHex).copy(alpha = settings.visibilityPercent / 100f),
                ),
            )
        } else {
            val selectedPath = if (Build.VERSION.SDK_INT < 31 && settings.blurRadius > 0) {
                settings.blurredPhotoPath ?: settings.photoPath
            } else {
                settings.photoPath
            }
            val bitmap by produceState<android.graphics.Bitmap?>(null, selectedPath) {
                value = withContext(Dispatchers.IO) { selectedPath?.let(BitmapFactory::decodeFile) }
            }
            DisposableEffect(bitmap) {
                onDispose { bitmap?.takeUnless { it.isRecycled }?.recycle() }
            }
            bitmap?.let { image ->
                Image(
                    bitmap = image.asImageBitmap(),
                    contentDescription = null,
                    contentScale = if (settings.contentScale == "fit") ContentScale.Fit else ContentScale.Crop,
                    alpha = settings.visibilityPercent / 100f,
                    modifier = Modifier.fillMaxSize().then(
                        if (Build.VERSION.SDK_INT >= 31 && settings.blurRadius > 0) {
                            Modifier.graphicsLayer {
                                renderEffect = RenderEffect.createBlurEffect(
                                    settings.blurRadius.toFloat(),
                                    settings.blurRadius.toFloat(),
                                    Shader.TileMode.CLAMP,
                                ).asComposeRenderEffect()
                            }
                        } else {
                            Modifier
                        },
                    ),
                )
            }
        }
        if (settings.overlayPercent > 0) {
            Box(
                modifier = Modifier.fillMaxSize().background(
                    pageColor.copy(alpha = settings.overlayPercent / 100f),
                ),
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
    headerHeight: Dp,
    periodRowHeight: Dp,
    visibleDayCount: Int,
    background: TimetableBackgroundSettings,
    modifier: Modifier,
) {
    val todayIndex = remember(snapshot.weekRange, today) {
        (0 until visibleDayCount).firstOrNull { snapshot.weekRange.startDate.plusDays(it.toLong()) == today }
    }
    val timeline = remember(snapshot.weekRange, today, currentTime) {
        todayIndex?.let { day -> currentTimeline(day, currentTime) }
    }

    Layout(
        modifier = modifier,
        content = {
            for (day in 0 until visibleDayCount) {
                val date = snapshot.weekRange.startDate.plusDays(day.toLong())
                DayHeader(
                    date = date,
                    isToday = day == todayIndex,
                    hasBackground = background.enabled,
                    modifier = Modifier.layoutId(GridSlot.Header(day)),
                )
            }
            for (period in 1..PeriodCount) {
                PeriodAxis(
                    period = period,
                    modifier = Modifier.layoutId(GridSlot.Axis(period)),
                )
                for (day in 0 until visibleDayCount) {
                    val date = snapshot.weekRange.startDate.plusDays(day.toLong())
                    EmptyGridCell(
                        isToday = day == todayIndex,
                        date = date,
                        period = period,
                        onClick = { onEmptyCellClick(date, period) },
                        hasBackground = background.enabled,
                        modifier = Modifier.layoutId(GridSlot.Cell(day, period)),
                    )
                }
            }
            snapshot.items.filter { it.dayIndex < visibleDayCount }.forEach { item ->
                TimetableItemCard(
                    item = item,
                    onClick = { onItemClick(item) },
                    opacity = if (background.enabled) background.courseOpacityPercent / 100f else 1f,
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
                        .testTag("timetable-current-time")
                        .semantics { contentDescription = "当前时间" }
                        .background(MaterialTheme.colorScheme.error),
                )
            }
        },
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val axisWidth = AxisWidth.roundToPx()
        val headerHeightPx = headerHeight.roundToPx()
        val rowHeight = periodRowHeight.roundToPx()
        val gap = GridGap.roundToPx()
        val dayWidth = (width - axisWidth) / visibleDayCount.toFloat()

        val placements = measurables.map { measurable ->
            val slot = measurable.layoutId as GridSlot
            val childConstraints = when (slot) {
                is GridSlot.Header -> Constraints.fixed(dayWidth.roundToInt(), headerHeightPx)
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
                        y = headerHeightPx + (slot.period - 1) * rowHeight
                    }
                    is GridSlot.Cell -> {
                        x = axisWidth + (slot.day * dayWidth).roundToInt() + gap
                        y = headerHeightPx + (slot.period - 1) * rowHeight + gap
                    }
                    is GridSlot.Item -> {
                        val laneWidth = dayWidth / slot.item.laneCount
                        x = axisWidth + (slot.item.dayIndex * dayWidth).roundToInt() +
                            (slot.item.lane * laneWidth).roundToInt() + gap
                        y = headerHeightPx + (slot.item.startPeriod - 1) * rowHeight + gap
                    }
                    is GridSlot.Timeline -> {
                        x = axisWidth + (slot.day * dayWidth).roundToInt() + gap
                        y = headerHeightPx + (slot.rowPosition * rowHeight).roundToInt()
                    }
                }
                placeable.placeRelative(x, y)
            }
        }
    }
}

@Composable
private fun DayHeader(
    date: LocalDate,
    isToday: Boolean,
    hasBackground: Boolean,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.padding(vertical = LeafySpacing.tiny),
        shape = GridCellShape,
        color = if (isToday) {
            MaterialTheme.leafySurfaces.accentSoft.copy(alpha = if (hasBackground) 0.82f else 1f)
        } else {
            MaterialTheme.leafySurfaces.page.copy(alpha = if (hasBackground) 0.64f else 1f)
        },
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
        ) {
            Text(
                text = if (isToday) "今天" else dayLabels[date.dayOfWeek.value - 1],
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1,
            )
            Text(
                text = date.format(DateTimeFormatter.ofPattern("M/d")),
                style = MaterialTheme.typography.labelSmall,
                color = if (isToday) {
                    MaterialTheme.colorScheme.onPrimaryContainer
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun PeriodAxis(period: Int, modifier: Modifier = Modifier) {
    val slot = TimetablePeriodSchedule.slot(period)
    Column(
        modifier = modifier.padding(top = LeafySpacing.tiny, end = LeafySpacing.tiny),
        horizontalAlignment = Alignment.End,
    ) {
        Text(
            text = period.toString(),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = slot?.startText.orEmpty(),
            style = MaterialTheme.typography.labelSmall.copy(
                fontSize = AxisTimeFontSize,
                lineHeight = AxisTimeLineHeight,
            ),
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
    hasBackground: Boolean,
    modifier: Modifier = Modifier,
) {
    Surface(
        onClick = onClick,
        modifier = modifier.testTag("timetable-cell-${date}-$period").semantics {
            contentDescription = "${date.monthValue}月${date.dayOfMonth}日 第${period}节，添加日程"
        },
        shape = GridCellShape,
        color = if (isToday) {
            MaterialTheme.leafySurfaces.accentSoft.copy(alpha = if (hasBackground) 0.48f else 0.6f)
        } else {
            MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = if (hasBackground) 0.42f else 0.62f)
        },
    ) {}
}

@Composable
private fun TimetableItemCard(
    item: TimetableGridItem,
    onClick: () -> Unit,
    opacity: Float,
    modifier: Modifier = Modifier,
) {
    val courseColors = MaterialTheme.leafyCourseColors
    val (containerColor, contentColor) = when (item.type) {
        TimetableGridItemType.COURSE -> courseColors.containers[
            stableCourseColorIndex(item.title, courseColors.containers.size)
        ] to courseColors.content
        TimetableGridItemType.EXAM -> MaterialTheme.colorScheme.tertiaryContainer to
            MaterialTheme.colorScheme.onTertiaryContainer
        TimetableGridItemType.SCHEDULE -> MaterialTheme.colorScheme.secondaryContainer to
            MaterialTheme.colorScheme.onSecondaryContainer
    }
    Surface(
        onClick = onClick,
        modifier = modifier.testTag("timetable-item-${item.stableId}").semantics(mergeDescendants = true) {
            contentDescription = "${item.title}，第${item.startPeriod}至${item.endPeriod}节"
        },
        shape = GridCellShape,
        color = containerColor.copy(alpha = opacity.coerceIn(0.35f, 1f)),
        contentColor = contentColor,
        shadowElevation = LeafyElevation.flat,
    ) {
        Column(modifier = Modifier.fillMaxSize().padding(LeafySpacing.tiny)) {
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
                    color = contentColor.copy(alpha = 0.78f),
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

private fun parseBackgroundColor(value: String): Color = runCatching {
    Color(android.graphics.Color.parseColor(value))
}.getOrDefault(Color(0xFFDDE9DF))
