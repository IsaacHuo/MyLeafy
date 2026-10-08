package com.myleafy.android.features.timetable.presentation

import kotlin.math.roundToInt

/** Both the fixed axis and the paged grid place rows against these cumulative pixel edges. */
internal class TimetableGridGeometry(height: Int, headerHeight: Int, maximumRowHeight: Float) {
    val header = headerHeight.coerceIn(0, height)
    private val body = (height - header).coerceAtMost((maximumRowHeight * 13).roundToInt())
    fun rowEdge(index: Int): Int = header + (body * index / 13f).roundToInt()
    fun rowHeight(period: Int): Int = rowEdge(period) - rowEdge(period - 1)
    fun timelineY(rowPosition: Float): Int = header + (body * rowPosition / 13f).roundToInt()
}
