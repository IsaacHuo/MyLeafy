package com.myleafy.android.features.schedule

import java.time.Duration
import java.time.Instant

/**
 * 个人日程倒计时文案（对应 iOS `CountdownEventRow.countdownDescription`）。
 * 仅本地计算，不依赖学校数据。
 */
object ScheduleCountdown {

    fun description(startsAtMillis: Long, nowMillis: Long = System.currentTimeMillis()): String {
        val remaining = Duration.ofMillis(startsAtMillis - nowMillis)
        if (remaining.isNegative || remaining.isZero) return "已开始"
        val totalHours = remaining.toHours()
        if (totalHours >= 24) {
            val days = totalHours / 24
            val hours = totalHours % 24
            return "还有 $days 天 $hours 小时"
        }
        val minutes = remaining.toMinutes() % 60
        return "还有 $totalHours 小时 $minutes 分钟"
    }

    fun instant(startsAtMillis: Long): Instant = Instant.ofEpochMilli(startsAtMillis)
}
