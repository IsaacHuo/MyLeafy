package com.myleafy.android.features.schedule

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import java.io.File
import java.io.FileOutputStream
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * 生成「记录日迹」分享图。只包含本机汇总数字，不包含随记正文与标签名称
 * （对应 iOS `ScheduleMemoStatisticsShareCard`）。
 */
object ScheduleStatisticsShareImage {

    private const val width = 1080
    private const val height = 1500

    fun render(
        context: Context,
        statistics: ScheduleMemoStatistics,
        accentColor: Int,
        now: LocalDate = LocalDate.now(scheduleCampusZone),
    ): File {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        val margin = 72f
        var y = 150f

        paint.color = Color.parseColor("#1B1B1B")
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.textSize = 60f
        canvas.drawText("记录日迹", margin, y, paint)
        y += 56f
        paint.typeface = Typeface.DEFAULT
        paint.textSize = 34f
        paint.color = Color.parseColor("#6B6B6B")
        canvas.drawText("${statistics.selectedYear} 年 · MyLeafy", margin, y, paint)
        y += 72f

        y = drawMetrics(canvas, paint, statistics, margin, y, accentColor)
        y = drawAnnualBars(canvas, paint, statistics, margin, y, accentColor)
        y = drawHeatmap(canvas, paint, statistics, margin, y, accentColor)

        paint.typeface = Typeface.DEFAULT
        paint.textSize = 28f
        paint.color = Color.parseColor("#8A8A8A")
        canvas.drawText("图片只包含本机汇总统计，不包含随记正文和标签名称。", margin, y, paint)
        y += 44f
        canvas.drawText(
            "生成时间：" + now.format(DateTimeFormatter.ofPattern("yyyy-MM-dd")),
            margin,
            y,
            paint,
        )

        val directory = File(context.cacheDir, "schedule-exports").apply { mkdirs() }
        val file = File(directory, "MyLeafy-statistics-${System.currentTimeMillis()}.png")
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        return file
    }

    private fun drawMetrics(
        canvas: Canvas,
        paint: Paint,
        statistics: ScheduleMemoStatistics,
        margin: Float,
        top: Float,
        accentColor: Int,
    ): Float {
        val items = listOf(
            "本年随记" to statistics.selectedYearMonths.sumOf { it.memoCount }.toString(),
            "本年记录天数" to statistics.selectedYearMonths.sumOf { it.recordingDayCount }.toString(),
            "最长连续" to "${statistics.longestStreak} 天",
        )
        val cardWidth = (width - margin * 2 - 32f * 2) / 3f
        items.forEachIndexed { index, (label, value) ->
            val left = margin + index * (cardWidth + 32f)
            paint.color = Color.parseColor("#F3F6F1")
            paint.style = Paint.Style.FILL
            canvas.drawRoundRect(RectF(left, top, left + cardWidth, top + 170f), 28f, 28f, paint)
            paint.color = accentColor
            paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            paint.textSize = 52f
            canvas.drawText(value, left + 32f, top + 74f, paint)
            paint.color = Color.parseColor("#6B6B6B")
            paint.typeface = Typeface.DEFAULT
            paint.textSize = 30f
            canvas.drawText(label, left + 32f, top + 128f, paint)
        }
        return top + 170f + 64f
    }

    private fun drawAnnualBars(
        canvas: Canvas,
        paint: Paint,
        statistics: ScheduleMemoStatistics,
        margin: Float,
        top: Float,
        accentColor: Int,
    ): Float {
        paint.color = Color.parseColor("#1B1B1B")
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.textSize = 36f
        canvas.drawText("全年记录频率", margin, top, paint)

        val chartTop = top + 40f
        val chartHeight = 260f
        val max = statistics.selectedYearMonths.maxOf { it.memoCount }.coerceAtLeast(1)
        val usable = width - margin * 2
        val slot = usable / 12f
        val barWidth = slot * 0.5f
        statistics.selectedYearMonths.forEachIndexed { index, month ->
            val ratio = month.memoCount.toFloat() / max
            val barHeight = (chartHeight * ratio).coerceAtLeast(if (month.memoCount > 0) 8f else 0f)
            val left = margin + index * slot + (slot - barWidth) / 2f
            val topEdge = chartTop + chartHeight - barHeight
            paint.color = if (month.memoCount > 0) accentColor else Color.parseColor("#E3E8E0")
            paint.style = Paint.Style.FILL
            canvas.drawRoundRect(RectF(left, topEdge, left + barWidth, chartTop + chartHeight), 8f, 8f, paint)
            paint.color = Color.parseColor("#8A8A8A")
            paint.textSize = 24f
            paint.typeface = Typeface.DEFAULT
            canvas.drawText(month.month.toString(), left + barWidth / 2f - 8f, chartTop + chartHeight + 34f, paint)
        }
        return chartTop + chartHeight + 80f
    }

    private fun drawHeatmap(
        canvas: Canvas,
        paint: Paint,
        statistics: ScheduleMemoStatistics,
        margin: Float,
        top: Float,
        accentColor: Int,
    ): Float {
        paint.color = Color.parseColor("#1B1B1B")
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.textSize = 36f
        canvas.drawText("近 30 天", margin, top, paint)
        paint.typeface = Typeface.DEFAULT
        paint.textSize = 30f
        paint.color = Color.parseColor("#6B6B6B")
        canvas.drawText(
            "${statistics.recent30DayMemoCount} 条 · ${statistics.recent30DayRecordingDayCount} 天",
            margin + 210f,
            top,
            paint,
        )

        val start = top + 36f
        val cell = (width - margin * 2 - 6 * 12f) / 7f
        val gap = 12f
        statistics.recent30Days.takeLast(28).forEachIndexed { index, day ->
            val row = index / 7
            val column = index % 7
            val left = margin + column * (cell + gap)
            val topEdge = start + row * (cell + gap)
            paint.color = when {
                day.count <= 0 -> Color.parseColor("#EEF1EC")
                day.count == 1 -> blend(accentColor, 0.28f)
                day.count == 2 -> blend(accentColor, 0.5f)
                day.count == 3 -> blend(accentColor, 0.72f)
                else -> accentColor
            }
            paint.style = Paint.Style.FILL
            canvas.drawRoundRect(RectF(left, topEdge, left + cell, topEdge + cell), 16f, 16f, paint)
        }
        return start + 4 * (cell + gap) + 48f
    }

    private fun blend(color: Int, ratio: Float): Int {
        val r = (Color.red(color) * ratio + 255 * (1 - ratio)).toInt()
        val g = (Color.green(color) * ratio + 255 * (1 - ratio)).toInt()
        val b = (Color.blue(color) * ratio + 255 * (1 - ratio)).toInt()
        return Color.rgb(r, g, b)
    }
}
