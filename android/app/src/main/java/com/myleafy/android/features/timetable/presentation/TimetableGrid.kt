package com.myleafy.android.features.timetable.presentation

import android.graphics.BitmapFactory
import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.features.timetable.domain.TimetableGridItem
import com.myleafy.android.features.timetable.domain.TimetableGridItemType
import com.myleafy.android.features.timetable.domain.TimetableGridSnapshot
import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import com.myleafy.android.ui.theme.LeafyElevation
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyTimetableTokens
import com.myleafy.android.ui.theme.LeafyTimetableBackgroundFallback
import com.myleafy.android.ui.theme.LeafyTimetableType
import com.myleafy.android.ui.theme.leafyCourseColors
import com.myleafy.android.ui.theme.leafySurfaces
import java.time.LocalDate
import java.time.LocalTime
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val PeriodCount = 13
private val GridCellShape = RoundedCornerShape(LeafyTimetableTokens.cellCornerRadius)

/**
 * 课程卡内部的文字取舍。网格几何（行高、列宽、圆角）仍由 [LeafyTimetableTokens] 决定，
 * 这里只回答一个问题：给定卡片高度，课程名和地点各能放几行。
 * 冲突窄列与矮行下地点会整段省略，完整信息仍由 semantics 提供。
 */
private object CourseCardText {
    val padding = LeafySpacing.tiny
    val lineSpacing = LeafySpacing.hairline
    const val titleMaxLines = 3
    const val titleMaxLinesNarrowLane = 4
    const val subtitleMaxLines = 2
    const val subtitleMaxLinesNarrowLane = 1
}

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
    val headerHeight = timetableHeaderHeight()
    BoxWithConstraints(modifier = modifier.fillMaxSize().testTag("timetable-grid")) {
        val visibleDayCount = if (showWeekends) 7 else 5
        val contentWidth = maxWidth
        // The timetable is a single viewport: rows compress to the available height
        // instead of turning the whole grid into a vertically scrolling surface.
        val minimumBodyHeight = LeafyTimetableTokens.minimumPeriodRowHeight * PeriodCount
        val periodRowHeight = ((maxHeight - headerHeight).coerceAtLeast(minimumBodyHeight) / PeriodCount)
            .coerceAtMost(LeafyTimetableTokens.maximumPeriodRowHeight)
        val contentHeight = headerHeight + periodRowHeight * PeriodCount
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
                headerHeight = headerHeight,
                periodRowHeight = periodRowHeight,
                visibleDayCount = visibleDayCount,
                background = background,
                modifier = Modifier.width(contentWidth).height(contentHeight),
            )
        }
    }
}

/**
 * 表头高度按内容推导：星期文字 + 日期圆点 + 上下内边距。
 * 100% 字体下是 16 + 28 + 8 = 52dp，比旧的 44dp 固定值高，日期不再被压；
 * 放大字体时两项都跟着 fontScale 长，所以表头继续变高而不是裁掉日期。
 * 课表其余高度仍按 13 节压缩，不抵消 fontScale。
 */
@Composable
private fun timetableHeaderHeight(): Dp {
    val density = LocalDensity.current
    val weekdayHeight = with(density) { MaterialTheme.typography.labelSmall.lineHeight.toDp() }
    return weekdayHeight + timetableDateIndicatorSize() + LeafySpacing.tiny * 2
}

/**
 * 日期圆点直径取日号行高与基准直径的较大者，同样不抵消 fontScale。
 * 100% 字体下等于 [LeafyTimetableTokens.dateIndicatorSize]；放大后两位数日号仍放得进圆底。
 */
@Composable
private fun timetableDateIndicatorSize(): Dp {
    val density = LocalDensity.current
    val numberLineHeight = with(density) { LeafyTimetableType.dayNumber.lineHeight.toDp() }
    return maxOf(numberLineHeight, LeafyTimetableTokens.dateIndicatorSize)
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
                value = withContext(Dispatchers.IO) { selectedPath?.let(::decodeTimetableBackground) }
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

private fun decodeTimetableBackground(path: String, maxSide: Int = 1_920): android.graphics.Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > maxSide * 2) sample *= 2
    return BitmapFactory.decodeFile(
        path,
        BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = android.graphics.Bitmap.Config.ARGB_8888
        },
    )
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
        todayIndex?.let { currentTimeline(currentTime) }
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
                    rowHeight = periodRowHeight,
                    modifier = Modifier
                        .layoutId(GridSlot.Item(item))
                        .zIndex(1f),
                )
            }
            if (timeline != null) {
                Box(
                    modifier = Modifier
                        .layoutId(GridSlot.Timeline(timeline.rowPosition))
                        .zIndex(2f)
                        .height(LeafyTimetableTokens.currentTimeIndicator)
                        .testTag("timetable-current-time")
                        .semantics { contentDescription = "当前时间" }
                        .background(MaterialTheme.colorScheme.primary),
                )
            }
        },
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val axisWidth = LeafyTimetableTokens.axisWidth.roundToPx()
        val headerHeightPx = headerHeight.roundToPx()
        val rowHeight = periodRowHeight.roundToPx()
        val gap = LeafyTimetableTokens.gridGap.roundToPx()
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
                    ((dayWidth * visibleDayCount).roundToInt() - gap * 2).coerceAtLeast(1),
                    LeafyTimetableTokens.currentTimeIndicator.roundToPx(),
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
                        x = axisWidth + gap
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
    Column(
        modifier = modifier.padding(vertical = LeafySpacing.tiny),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = dayLabels[date.dayOfWeek.value - 1],
            style = MaterialTheme.typography.labelSmall,
            color = if (isToday) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
        )
        // 只有“今天”画圆底；其余日期只留文本，避免透明 Surface 占位。
        val todayIndicator = if (isToday) {
            Modifier.background(
                color = MaterialTheme.colorScheme.primary.copy(alpha = if (hasBackground) 0.9f else 1f),
                shape = CircleShape,
            )
        } else {
            Modifier
        }
        Box(
            modifier = Modifier.size(timetableDateIndicatorSize()).then(todayIndicator),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = date.dayOfMonth.toString(),
                style = LeafyTimetableType.dayNumber,
                color = if (isToday) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
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
            // 节次序号与课程名共用同一个 11sp / SemiBold 紧凑数字角色。
            style = LeafyTimetableType.courseTitle,
        )
        Text(
            text = slot?.startText.orEmpty(),
            style = LeafyTimetableType.axisTime,
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
    // 每个空格都用浅色表面 + 极细描边呈现，让 7×13 的网格结构始终清晰可见；
    // 有自定义背景时改用半透明填充压住照片，“今天”列用强调色区分。
    val fill = when {
        isToday -> MaterialTheme.leafySurfaces.accentSoft.copy(alpha = if (hasBackground) 0.5f else 0.6f)
        hasBackground -> MaterialTheme.leafySurfaces.content.copy(alpha = 0.32f)
        else -> MaterialTheme.leafySurfaces.content
    }
    val border = BorderStroke(
        width = LeafySpacing.hairline,
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = if (hasBackground) 0.5f else 0.65f),
    )
    Surface(
        onClick = onClick,
        modifier = modifier.testTag("timetable-cell-${date}-$period").semantics {
            contentDescription = "${date.monthValue}月${date.dayOfMonth}日 第${period}节，添加日程"
        },
        shape = GridCellShape,
        color = fill,
        border = border,
    ) {}
}

@Composable
private fun TimetableItemCard(
    item: TimetableGridItem,
    onClick: () -> Unit,
    opacity: Float,
    rowHeight: Dp,
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
    // 字号只由可用列宽决定，与跨节无关：11sp / 14dp 在冲突窄列也放得下，
    // 宽屏富余的列宽交给行数，而不是换一套更大的字号。
    val subtitle = item.subtitle?.takeIf { it.isNotBlank() }
    val cardHeight = rowHeight * item.periodSpan - LeafyTimetableTokens.gridGap * 2
    val density = LocalDensity.current
    val titleLineHeight = with(density) { LeafyTimetableType.courseTitle.lineHeight.toDp() }
    val subtitleLineHeight = with(density) { LeafyTimetableType.courseSubtitle.lineHeight.toDp() }
    val lines = courseCardLines(
        cardHeight = cardHeight,
        titleLineHeight = titleLineHeight,
        subtitleLineHeight = subtitleLineHeight,
        lineSpacing = CourseCardText.lineSpacing,
        hasSubtitle = subtitle != null,
        // 冲突窄列一字一行，标题多留一行才能放下「高等数学」这类四字课名；
        // 上限只是上限，实际行数仍由卡片高度与 fontScale 决定。
        maxTitleLines = if (item.laneCount > 1) {
            CourseCardText.titleMaxLinesNarrowLane
        } else {
            CourseCardText.titleMaxLines
        },
        maxSubtitleLines = if (item.laneCount > 1) {
            CourseCardText.subtitleMaxLinesNarrowLane
        } else {
            CourseCardText.subtitleMaxLines
        },
    )
    Surface(
        onClick = onClick,
        modifier = modifier.testTag("timetable-item-${item.stableId}").semantics(mergeDescendants = true) {
            // 视觉上可能省略地点，朗读始终包含完整信息。
            contentDescription = buildString {
                append(item.title)
                append("，第${item.startPeriod}至${item.endPeriod}节")
                subtitle?.let { append("，$it") }
            }
        },
        shape = GridCellShape,
        color = containerColor.copy(alpha = opacity.coerceIn(0.35f, 1f)),
        contentColor = contentColor,
        shadowElevation = LeafyElevation.flat,
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(CourseCardText.padding),
            verticalArrangement = Arrangement.spacedBy(CourseCardText.lineSpacing),
        ) {
            Text(
                text = item.title,
                style = LeafyTimetableType.courseTitle,
                maxLines = lines.title,
                overflow = TextOverflow.Ellipsis,
            )
            if (subtitle != null && lines.subtitle > 0) {
                Text(
                    text = subtitle,
                    style = LeafyTimetableType.courseSubtitle,
                    color = contentColor.copy(alpha = 0.78f),
                    maxLines = lines.subtitle,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

private data class CourseCardLines(val title: Int, val subtitle: Int)

/**
 * 先保证课程名占行，剩下的行高才分给地点；不足一行就整段省略副文。
 * 行高由 [LeafyTimetableType] 的 TextStyle 经 Density 换算，因此系统字体放大时
 * 会自动少放几行，而不是把文字压扁硬塞。
 */
private fun courseCardLines(
    cardHeight: Dp,
    titleLineHeight: Dp,
    subtitleLineHeight: Dp,
    lineSpacing: Dp,
    hasSubtitle: Boolean,
    maxTitleLines: Int,
    maxSubtitleLines: Int,
): CourseCardLines {
    val verticalSpace = cardHeight - CourseCardText.padding * 2
    val titleLines = if (titleLineHeight <= 0.dp) {
        1
    } else {
        (verticalSpace / titleLineHeight).toInt().coerceIn(1, maxTitleLines)
    }
    if (!hasSubtitle || subtitleLineHeight <= 0.dp) return CourseCardLines(titleLines, 0)
    // 标题与副文之间还有一条 lineSpacing，分配副文行数前必须先扣掉，
    // 否则最后一行会顶出卡片被裁掉。
    val remaining = verticalSpace - titleLineHeight * titleLines - lineSpacing
    val subtitleLines = if (remaining <= 0.dp) {
        0
    } else {
        (remaining / subtitleLineHeight).toInt().coerceIn(0, maxSubtitleLines)
    }
    return CourseCardLines(titleLines, subtitleLines)
}

private fun currentTimeline(time: LocalTime): CurrentTimeline? {
    val minutes = time.hour * 60 + time.minute
    val slot = TimetablePeriodSchedule.periodForFocus(minutes) ?: return null
    if (minutes < TimetablePeriodSchedule.slots.first().startMinutes ||
        minutes > TimetablePeriodSchedule.slots.last().endMinutes
    ) return null
    val fraction = ((minutes - slot.startMinutes).toFloat() / (slot.endMinutes - slot.startMinutes))
        .coerceIn(0f, 1f)
    return CurrentTimeline(rowPosition = (slot.period - 1) + fraction)
}

private data class CurrentTimeline(val rowPosition: Float)

private sealed interface GridSlot {
    data class Header(val day: Int) : GridSlot
    data class Axis(val period: Int) : GridSlot
    data class Cell(val day: Int, val period: Int) : GridSlot
    data class Item(val item: TimetableGridItem) : GridSlot
    data class Timeline(val rowPosition: Float) : GridSlot
}

private val dayLabels = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")

private fun parseBackgroundColor(value: String): Color = runCatching {
    Color(android.graphics.Color.parseColor(value))
}.getOrDefault(LeafyTimetableBackgroundFallback)
