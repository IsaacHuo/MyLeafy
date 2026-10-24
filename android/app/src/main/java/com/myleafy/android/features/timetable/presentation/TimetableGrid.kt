package com.myleafy.android.features.timetable.presentation

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import com.myleafy.android.features.timetable.domain.TimetableGridItem
import com.myleafy.android.features.timetable.domain.TimetableGridItemType
import com.myleafy.android.features.timetable.domain.TimetableGridSnapshot
import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import com.myleafy.android.ui.theme.LeafyAlpha
import com.myleafy.android.ui.theme.LeafyElevation
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyStroke
import com.myleafy.android.ui.theme.LeafyTimetableTokens
import com.myleafy.android.ui.theme.LeafyTimetableType
import com.myleafy.android.ui.theme.leafyCourseColors
import com.myleafy.android.ui.theme.leafySurfaces
import java.time.LocalDate
import java.time.LocalTime
import kotlin.math.roundToInt

private val GridCellShape = RoundedCornerShape(LeafyTimetableTokens.cellCornerRadius)

/**
 * 课程卡内部的文字取舍。网格几何（行高、列宽、圆角）仍由 [LeafyTimetableTokens] 决定，
 * 这里只回答一个问题：给定卡片高度，课程名和地点各能放几行。
 * 冲突窄列与矮行下地点会整段省略，完整信息仍由 semantics 提供。
 */
private object CourseCardText {
    val padding = 3.dp
    val lineSpacing = LeafySpacing.hairline
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
    showAxis: Boolean = true,
    background: TimetableBackgroundSettings = TimetableBackgroundSettings(),
) {
    val headerHeight = timetableHeaderHeight()
    val axisWidth = if (showAxis) timetableAxisWidth() else 0.dp
    val viewConfiguration = LocalViewConfiguration.current
    val gridViewConfiguration = remember(viewConfiguration) {
        object : ViewConfiguration by viewConfiguration {
            override val minimumTouchTargetSize = DpSize.Zero
        }
    }
    BoxWithConstraints(modifier = modifier.fillMaxSize().testTag("timetable-grid")) {
        val visibleDayCount = if (showWeekends) 7 else 5
        val contentWidth = maxWidth
        val periodCount = TimetablePeriodSchedule.slots.size.coerceAtLeast(1)
        // The timetable is a single viewport: rows compress to the available height
        // instead of turning the whole grid into a vertically scrolling surface.
        val minimumBodyHeight = LeafyTimetableTokens.minimumPeriodRowHeight * periodCount
        val periodRowHeight = ((maxHeight - headerHeight).coerceAtLeast(minimumBodyHeight) / periodCount)
            .coerceAtMost(LeafyTimetableTokens.maximumPeriodRowHeight)
        val contentHeight = headerHeight + periodRowHeight * periodCount
        Box(
            modifier = Modifier
                .fillMaxSize(),
            contentAlignment = Alignment.TopCenter,
        ) {
            // 密集格子的触摸范围以可见边界为准，避免相邻课程的 48dp 扩展区域互相覆盖。
            CompositionLocalProvider(
                LocalViewConfiguration provides gridViewConfiguration,
                LocalMinimumInteractiveComponentSize provides 0.dp,
            ) {
                TimetableGridLayout(
                    snapshot = snapshot,
                    today = today,
                    currentTime = currentTime,
                    onEmptyCellClick = onEmptyCellClick,
                    onItemClick = onItemClick,
                    headerHeight = headerHeight,
                    periodRowHeight = periodRowHeight,
                    periodCount = periodCount,
                    visibleDayCount = visibleDayCount,
                    axisWidth = axisWidth,
                    background = background,
                    modifier = Modifier.width(contentWidth).height(contentHeight),
                )
            }
        }
    }
}

/** 按系统字体的实际字宽分配时间轴，保留节次、时间间隔，避免挤占课程列。 */
@Composable
internal fun timetableAxisWidth(): Dp {
    val density = LocalDensity.current
    val measurer = rememberTextMeasurer()
    val periodCount = TimetablePeriodSchedule.slots.size.coerceAtLeast(1)
    val periodWidth = (1..periodCount).maxOf {
        measurer.measure(it.toString(), LeafyTimetableType.axisPeriod).size.width
    }
    val timeWidth = (1..periodCount).flatMap { period ->
        TimetablePeriodSchedule.slot(period)?.let { listOf(it.startText, it.endText) }.orEmpty()
    }.maxOf { measurer.measure(it, LeafyTimetableType.axisTime).size.width }
    return maxOf(LeafyTimetableTokens.axisWidth, with(density) { maxOf(periodWidth, timeWidth).toDp() } + 6.dp)
}

/**
 * 表头高度按内容推导：星期文字 + 日期圆点 + 上下内边距。
 * 100% 字体下是 16 + 28 + 8 = 52dp，比旧的 44dp 固定值高，日期不再被压；
 * 放大字体时两项都跟着 fontScale 长，所以表头继续变高而不是裁掉日期。
 * 课表其余高度仍按 13 节压缩，不抵消 fontScale。
 */
@Composable
internal fun timetableHeaderHeight(): Dp {
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
    return maxOf(numberLineHeight + LeafySpacing.tiny * 2, LeafyTimetableTokens.dateIndicatorSize)
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
    periodCount: Int,
    visibleDayCount: Int,
    axisWidth: Dp,
    background: TimetableBackgroundSettings,
    modifier: Modifier,
) {
    val todayIndex = remember(snapshot.weekRange, today, visibleDayCount) {
        (0 until visibleDayCount).firstOrNull { snapshot.weekRange.startDate.plusDays(it.toLong()) == today }
    }
    val timeline = remember(snapshot.weekRange, today, todayIndex, currentTime) {
        todayIndex?.let { currentTimeline(currentTime) }
    }

    Layout(
        modifier = modifier.timetableAxisBackdrop(background.enabled, axisWidth),
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
            for (period in 1..periodCount) {
                if (axisWidth > 0.dp) PeriodAxis(
                    period = period,
                    rowHeight = periodRowHeight,
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
                    isToday = item.dayIndex == todayIndex,
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
        val axisWidthPx = axisWidth.roundToPx()
        val headerHeightPx = headerHeight.roundToPx()
        val geometry = TimetableGridGeometry(height, headerHeightPx, LeafyTimetableTokens.maximumPeriodRowHeight.toPx())
        val gap = LeafyTimetableTokens.gridGap.roundToPx()
        val dayWidth = (width - axisWidthPx) / visibleDayCount.toFloat()
        fun dayEdge(day: Int) = axisWidthPx + (day * dayWidth).roundToInt()

        val placements = measurables.map { measurable ->
            val slot = measurable.layoutId as GridSlot
            val childConstraints = when (slot) {
                is GridSlot.Header -> Constraints.fixed(dayEdge(slot.day + 1) - dayEdge(slot.day), geometry.header)
                is GridSlot.Axis -> Constraints.fixed(axisWidthPx, geometry.rowHeight(slot.period))
                is GridSlot.Cell -> Constraints.fixed(
                    (dayEdge(slot.day + 1) - dayEdge(slot.day) - gap * 2).coerceAtLeast(1),
                    (geometry.rowHeight(slot.period) - gap * 2).coerceAtLeast(1),
                )
                is GridSlot.Item -> {
                    val laneWidth = (dayEdge(slot.item.dayIndex + 1) - dayEdge(slot.item.dayIndex)).toFloat() / slot.item.laneCount
                    Constraints.fixed(
                        (((slot.item.lane + 1) * laneWidth).roundToInt() - (slot.item.lane * laneWidth).roundToInt() - gap * 2).coerceAtLeast(1),
                        (geometry.rowEdge(slot.item.endPeriod) - geometry.rowEdge(slot.item.startPeriod - 1) - gap * 2).coerceAtLeast(1),
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
                        x = dayEdge(slot.day)
                        y = 0
                    }
                    is GridSlot.Axis -> {
                        x = 0
                        y = geometry.rowEdge(slot.period - 1)
                    }
                    is GridSlot.Cell -> {
                        x = dayEdge(slot.day) + gap
                        y = geometry.rowEdge(slot.period - 1) + gap
                    }
                    is GridSlot.Item -> {
                        val laneWidth = (dayEdge(slot.item.dayIndex + 1) - dayEdge(slot.item.dayIndex)).toFloat() / slot.item.laneCount
                        x = dayEdge(slot.item.dayIndex) +
                            (slot.item.lane * laneWidth).roundToInt() + gap
                        y = geometry.rowEdge(slot.item.startPeriod - 1) + gap
                    }
                    is GridSlot.Timeline -> {
                        x = axisWidthPx + gap
                        y = geometry.timelineY(slot.rowPosition)
                    }
                }
                placeable.placeRelative(x, y)
            }
        }
    }
}

/** One axis shared by every week; geometry matches TimetableGridLayout pixel rounding. */
@Composable
internal fun TimetableFixedAxis(month: Int, modifier: Modifier = Modifier) {
    val header = timetableHeaderHeight()
    BoxWithConstraints(modifier.width(timetableAxisWidth()).testTag("timetable-fixed-axis")) {
        val periodCount = TimetablePeriodSchedule.slots.size.coerceAtLeast(1)
        val row = ((maxHeight - header).coerceAtLeast(LeafyTimetableTokens.minimumPeriodRowHeight * periodCount) / periodCount)
            .coerceAtMost(LeafyTimetableTokens.maximumPeriodRowHeight)
        Layout(content = {
            Box(Modifier.testTag("timetable-month").semantics(mergeDescendants = true) {}, contentAlignment = Alignment.Center) {
                Text("${month}月", style = LeafyTimetableType.axisTime)
            }
            for (period in 1..periodCount) PeriodAxis(period, row)
        }) { children, constraints ->
            val headerPx = header.roundToPx()
            val geometry = TimetableGridGeometry(constraints.maxHeight, headerPx, LeafyTimetableTokens.maximumPeriodRowHeight.toPx())
            val measured = children.mapIndexed { i, child -> child.measure(Constraints.fixed(constraints.maxWidth, if (i == 0) geometry.header else geometry.rowHeight(i))) }
            layout(constraints.maxWidth, constraints.maxHeight) {
                measured.forEachIndexed { i, child -> child.placeRelative(0, if (i == 0) 0 else geometry.rowEdge(i - 1)) }
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
private fun PeriodAxis(period: Int, rowHeight: Dp, modifier: Modifier = Modifier) {
    val slot = TimetablePeriodSchedule.slot(period)
    val startText = slot?.startText.orEmpty()
    val endText = slot?.endText.orEmpty()
    val density = LocalDensity.current
    val timeLineHeight = with(density) { LeafyTimetableType.axisTime.lineHeight.toDp() }
    val periodLineHeight = with(density) { LeafyTimetableType.axisPeriod.lineHeight.toDp() }
    // 先省略结束时间；极短行连开始时间也放不下时，保留完整节次与朗读区间，避免半行裁切。
    val showStart = startText.isNotEmpty() && rowHeight >= periodLineHeight + timeLineHeight
    val showEnd = endText.isNotEmpty() && rowHeight >= periodLineHeight + timeLineHeight * 2
    Column(
        modifier = modifier
            .padding(horizontal = 3.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = if (slot == null) "第${period}节" else "第${period}节，$startText 至 $endText"
            },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = period.toString(),
            style = LeafyTimetableType.axisPeriod,
            maxLines = 1,
            modifier = Modifier.testTag("timetable-axis-period-$period"),
        )
        if (showStart) {
            Text(
                text = startText,
                style = LeafyTimetableType.axisTime,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                modifier = Modifier.testTag("timetable-axis-start-$period"),
            )
        }
        if (showEnd) {
            Text(
                text = endText,
                style = LeafyTimetableType.axisTime,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                modifier = Modifier.testTag("timetable-axis-end-$period"),
            )
        }
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
    // 空白格只保留对齐参照：填充与描边都比课程块更弱，让课程块、今天和当前时间
    // 继续当视觉重点。有自定义背景时进一步降低存在感，“今天”列用强调色区分。
    val fill = when {
        isToday -> MaterialTheme.leafySurfaces.accentSoft.copy(alpha = if (hasBackground) 0.32f else 0.38f)
        hasBackground -> MaterialTheme.leafySurfaces.content.copy(
            alpha = LeafyTimetableTokens.emptyCellFillAlphaOnBackground,
        )
        // 与 iOS 的 cardBackground(0.62) 对齐：空白格是“很淡的卡片”，不是页面挖空。
        else -> MaterialTheme.leafySurfaces.content.copy(alpha = 0.55f)
    }
    val border = BorderStroke(
        width = LeafyStroke.hairline,
        color = MaterialTheme.colorScheme.outlineVariant.copy(
            alpha = if (hasBackground) {
                LeafyTimetableTokens.emptyCellBorderAlphaOnBackground
            } else {
                LeafyTimetableTokens.emptyCellBorderAlpha
            },
        ),
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
    isToday: Boolean,
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
    val subtitle = item.subtitle?.takeIf { it.isNotBlank() }
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
        border = BorderStroke(
            LeafyStroke.hairline,
            if (isToday) {
                MaterialTheme.colorScheme.primary.copy(alpha = 0.78f)
            } else {
                MaterialTheme.colorScheme.outlineVariant.copy(alpha = LeafyAlpha.cardBorder)
            },
        ),
        shadowElevation = if (MaterialTheme.colorScheme.background.luminance() > 0.5f) {
            LeafyElevation.resting
        } else {
            LeafyElevation.flat
        },
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val density = LocalDensity.current
            val measurer = rememberTextMeasurer()
            val availableWidth = with(density) { (maxWidth - CourseCardText.padding * 2).toPx() }
            val subtitleFits = subtitle != null && measurer.measure(
                subtitle.take(2) + "…", LeafyTimetableType.courseSubtitle,
            ).size.width <= availableWidth
            val titleLineHeight = with(density) { LeafyTimetableType.courseTitle.lineHeight.toDp() }
            val subtitleLineHeight = with(density) { LeafyTimetableType.courseSubtitle.lineHeight.toDp() }
            val lines = courseCardLines(
                cardHeight = maxHeight, titleLineHeight = titleLineHeight,
                subtitleLineHeight = subtitleLineHeight, lineSpacing = CourseCardText.lineSpacing,
                hasSubtitle = subtitleFits,
                maxTitleLines = Int.MAX_VALUE, maxSubtitleLines = 1,
            )
            Column(
                modifier = Modifier.fillMaxSize().padding(CourseCardText.padding),
                verticalArrangement = Arrangement.spacedBy(CourseCardText.lineSpacing),
            ) {
                Text(text = item.title, style = LeafyTimetableType.courseTitle,
                    maxLines = lines.title, overflow = TextOverflow.Ellipsis)
                if (subtitle != null && lines.subtitle > 0) {
                    Text(text = subtitle, style = LeafyTimetableType.courseSubtitle,
                        color = contentColor.copy(alpha = LeafyAlpha.subtitle), maxLines = lines.subtitle,
                        overflow = TextOverflow.Ellipsis)
                }
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
    if (verticalSpace <= 0.dp || titleLineHeight <= 0.dp) return CourseCardLines(1, 0)
    val maxTitleByHeight = (verticalSpace / titleLineHeight).toInt().coerceAtLeast(1)
    if (!hasSubtitle || subtitleLineHeight <= 0.dp) {
        return CourseCardLines(maxTitleByHeight.coerceAtMost(maxTitleLines).coerceAtLeast(1), 0)
    }
    // 标题与副文之间还有一条 lineSpacing，分配副文行数前必须先扣掉，
    // 否则最后一行会顶出卡片被裁掉。
    val maxTitleKeepingSubtitle =
        ((verticalSpace - lineSpacing - subtitleLineHeight) / titleLineHeight).toInt()
    // 课名少一行仍然可以用省略号表达，地点整段消失就没有线索了：
    // 只要“一行课名 + 一行地点”放得下，就先留出地点，再把剩下的行数给课名。
    val titleLines = if (maxTitleKeepingSubtitle >= 1) {
        minOf(maxTitleLines, maxTitleByHeight, maxTitleKeepingSubtitle).coerceAtLeast(1)
    } else {
        maxTitleByHeight.coerceAtMost(maxTitleLines).coerceAtLeast(1)
    }
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
