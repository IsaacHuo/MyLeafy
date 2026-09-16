package com.myleafy.android.features.schedule

import com.myleafy.android.core.data.local.ScheduleMemoEntity
import java.text.Normalizer
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * 日迹（随记）本机聚合与回顾逻辑（对应 iOS `ScheduleMemoModels` / `ScheduleMemoStatisticsView`）。
 *
 * 全部为纯函数，不依赖 Android 平台；随记已按校园身份 scopeKey 隔离，这里只做投影。
 */

val scheduleCampusZone: ZoneId = ZoneId.of("Asia/Shanghai")

/** 标签聚合结果。 [name] 保留首次出现的原始拼写，[count] 为去重后的随记数。 */
data class ScheduleMemoTagSummary(val name: String, val count: Int)

/** 大小写与变音符号无关的标签归一化，用于去重与排序。 */
internal fun foldTagKey(tag: String): String =
    Normalizer.normalize(tag, Normalizer.Form.NFKD)
        .replace(Regex("\\p{Mn}+"), "")
        .lowercase(Locale.ROOT)

/** 从随记正文解析 `#标签`（与 iOS `ScheduleMemoTagParser` 同构）。 */
object ScheduleMemoTagParser {
    private val regex = Regex("#([\\p{L}\\p{N}_-]+(?:/[\\p{L}\\p{N}_-]+)*)")

    fun tagsIn(body: String): List<String> {
        val seen = LinkedHashMap<String, String>()
        regex.findAll(body).forEach { match ->
            val raw = match.groupValues[1]
            val key = foldTagKey(raw)
            seen.putIfAbsent(key, raw)
        }
        return seen.values.toList()
    }

    fun decode(encoded: String): List<String> =
        encoded.split('\n').map(String::trim).filter(String::isNotEmpty)

    fun encode(tags: List<String>): String = tags.joinToString("\n")
}

object ScheduleMemoTagAggregator {

    /** 按标签名字母序聚合未删除随记的标签。 */
    fun summarize(memos: List<ScheduleMemoEntity>): List<ScheduleMemoTagSummary> {
        val names = LinkedHashMap<String, String>()
        val counts = LinkedHashMap<String, Int>()
        memos.asSequence()
            .filter { it.trashedAt == null }
            .flatMap { ScheduleMemoTagParser.decode(it.tags).asSequence() }
            .forEach { tag ->
                val key = foldTagKey(tag)
                names.putIfAbsent(key, tag)
                counts[key] = (counts[key] ?: 0) + 1
            }
        return counts.entries
            .sortedBy { it.key }
            .map { ScheduleMemoTagSummary(names.getValue(it.key), it.value) }
    }
}

enum class ScheduleMemoTimePeriod(val label: String) {
    EARLY_MORNING("清晨"),
    MORNING("上午"),
    AFTERNOON("下午"),
    EVENING("晚间"),
    LATE_NIGHT("深夜"),
    ;

    companion object {
        fun forHour(hour: Int): ScheduleMemoTimePeriod = when (hour) {
            in 5..8 -> EARLY_MORNING
            in 9..11 -> MORNING
            in 12..17 -> AFTERNOON
            in 18..23 -> EVENING
            else -> LATE_NIGHT
        }
    }
}

data class ScheduleMemoMonthStat(
    val month: Int,
    val memoCount: Int,
    val recordingDayCount: Int,
)

data class ScheduleMemoDayCount(val date: LocalDate, val count: Int)

data class ScheduleMemoStatistics(
    val memoCount: Int,
    val recordingDayCount: Int,
    val tagCount: Int,
    val currentStreak: Int,
    val longestStreak: Int,
    val selectedYear: Int,
    val availableYears: List<Int>,
    val selectedYearMonths: List<ScheduleMemoMonthStat>,
    val recent30DayMemoCount: Int,
    val previous30DayMemoCount: Int,
    val recent30DayRecordingDayCount: Int,
    val previous30DayRecordingDayCount: Int,
    val weekdayDistribution: List<Int>,
    val timePeriodDistribution: Map<ScheduleMemoTimePeriod, Int>,
    val topTags: List<ScheduleMemoTagSummary>,
    val firstRecordingDate: LocalDate?,
    val peakDate: LocalDate?,
    val peakMemoCount: Int,
    val recordingMonthCount: Int,
    val recent30Days: List<ScheduleMemoDayCount>,
)

object ScheduleMemoStatisticsCalculator {

    fun availableYears(memos: List<ScheduleMemoEntity>, now: LocalDate): List<Int> {
        val years = memos.asSequence()
            .filter { it.trashedAt == null }
            .map { createdDate(it, scheduleCampusZone).year }
            .toMutableSet()
        years += now.year
        return years.sorted()
    }

    fun calculate(
        memos: List<ScheduleMemoEntity>,
        selectedYear: Int,
        now: LocalDate,
        zone: ZoneId = scheduleCampusZone,
    ): ScheduleMemoStatistics {
        val active = memos.filter { it.trashedAt == null }
        val timestamps = active.map { createdDateTime(it, zone) }
        val counts = HashMap<LocalDate, Int>()
        timestamps.forEach { dateTime ->
            val day = dateTime.toLocalDate()
            counts[day] = (counts[day] ?: 0) + 1
        }
        val today = now
        val tagCount = ScheduleMemoTagAggregator.summarize(active).size

        val monthBuckets = (1..12).associateWith { month ->
            val inMonth = timestamps.filter { it.year == selectedYear && it.monthValue == month }
            ScheduleMemoMonthStat(
                month = month,
                memoCount = inMonth.size,
                recordingDayCount = inMonth.map { it.toLocalDate() }.toSet().size,
            )
        }.map { it.value }

        val recentStart = today.minusDays(29)
        val previousStart = today.minusDays(59)
        val previousEnd = today.minusDays(30)
        val recentRange = dayRange(recentStart, today)
        val previousRange = dayRange(previousStart, previousEnd)
        val recent30 = recentRange.map { day -> ScheduleMemoDayCount(day, counts[day] ?: 0) }
        val recent30Memos = recent30.sumOf { it.count }
        val recent30RecordingDays = recent30.count { it.count > 0 }
        val previous30Memos = previousRange.sumOf { counts[it] ?: 0 }
        val previous30RecordingDays = previousRange.count { (counts[it] ?: 0) > 0 }

        val weekdayDistribution = IntArray(7)
        val timePeriodDistribution = linkedMapOf<ScheduleMemoTimePeriod, Int>()
        ScheduleMemoTimePeriod.entries.forEach { timePeriodDistribution[it] = 0 }
        timestamps.forEach { dateTime ->
            val mondayBased = (dateTime.dayOfWeek.value + 6) % 7
            weekdayDistribution[mondayBased] += 1
            val period = ScheduleMemoTimePeriod.forHour(dateTime.hour)
            timePeriodDistribution[period] = (timePeriodDistribution[period] ?: 0) + 1
        }

        val topTags = ScheduleMemoTagAggregator.summarize(active)
            .sortedWith(compareByDescending<ScheduleMemoTagSummary> { it.count }.thenBy { foldTagKey(it.name) })
            .take(5)

        val firstRecordingDate = counts.keys.minOrNull()
        val peak = counts.maxWithOrNull(
            compareBy<Map.Entry<LocalDate, Int>> { it.value }.thenByDescending { it.key },
        )
        val recordingMonthCount = counts.keys.map { it.year * 100 + it.monthValue }.toSet().size

        return ScheduleMemoStatistics(
            memoCount = active.size,
            recordingDayCount = counts.size,
            tagCount = tagCount,
            currentStreak = currentStreak(counts.keys, today),
            longestStreak = longestStreak(counts.keys),
            selectedYear = selectedYear,
            availableYears = availableYears(active, today),
            selectedYearMonths = monthBuckets,
            recent30DayMemoCount = recent30Memos,
            previous30DayMemoCount = previous30Memos,
            recent30DayRecordingDayCount = recent30RecordingDays,
            previous30DayRecordingDayCount = previous30RecordingDays,
            weekdayDistribution = weekdayDistribution.toList(),
            timePeriodDistribution = timePeriodDistribution,
            topTags = topTags,
            firstRecordingDate = firstRecordingDate,
            peakDate = peak?.key,
            peakMemoCount = peak?.value ?: 0,
            recordingMonthCount = recordingMonthCount,
            recent30Days = recent30,
        )
    }

    private fun currentStreak(days: Set<LocalDate>, today: LocalDate): Int {
        var anchor = if (today in days) today else today.minusDays(1)
        if (anchor !in days) return 0
        var streak = 0
        while (anchor in days) {
            streak += 1
            anchor = anchor.minusDays(1)
        }
        return streak
    }

    private fun longestStreak(days: Set<LocalDate>): Int {
        if (days.isEmpty()) return 0
        val sorted = days.sorted()
        var longest = 1
        var current = 1
        for (index in 1 until sorted.size) {
            if (ChronoUnit.DAYS.between(sorted[index - 1], sorted[index]) == 1L) {
                current += 1
            } else {
                current = 1
            }
            if (current > longest) longest = current
        }
        return longest
    }
}

object ScheduleMemoReviewEngine {
    private const val DEFAULT_LIMIT = 5

    /**
     * 每日回顾选择：优先历年同日，其余按 `stableHash("年-月-日|id")` 确定性排序，
     * 再按页环形取样（对应 iOS `ScheduleMemoReviewEngine`）。
     */
    fun select(
        memos: List<ScheduleMemoEntity>,
        today: LocalDate,
        page: Int,
        limit: Int = DEFAULT_LIMIT,
        zone: ZoneId = scheduleCampusZone,
    ): List<ScheduleMemoEntity> {
        val candidates = memos.filter { it.trashedAt == null }
            .filter { createdDate(it, zone).isBefore(today) }
        if (candidates.isEmpty()) return emptyList()
        val anniversary = candidates
            .filter {
                val date = createdDate(it, zone)
                date.monthValue == today.monthValue && date.dayOfMonth == today.dayOfMonth
            }
            .sortedBy { it.createdAt }
        val anniversaryIds = anniversary.map { it.id }.toHashSet()
        val seed = "%04d-%02d-%02d".format(today.year, today.monthValue, today.dayOfMonth)
        val rest = candidates
            .filterNot { it.id in anniversaryIds }
            .sortedBy { stableHash("$seed|${it.id}") }
        val pool = anniversary + rest
        val start = if (pool.isEmpty()) 0 else (page.toLong() * limit % pool.size).toInt()
        val size = minOf(limit, pool.size)
        return List(size) { offset -> pool[(start + offset) % pool.size] }
    }

    /** FNV-1a 64-bit 稳定哈希（无符号比较语义与 iOS 一致）。 */
    internal fun stableHash(value: String): Long {
        var hash = -0x340d631b7bdddcdbL // 14695981039346656037
        value.toByteArray(Charsets.UTF_8).forEach { byte ->
            hash = hash xor (byte.toLong() and 0xff)
            hash *= 0x100000001b3L // 1099511628211
        }
        return hash
    }
}

object ScheduleMemoTextExporter {
    private const val separator = "----------------------------------------"

    /** 导出全部未删除随记为纯文本（对应 iOS `ScheduleMemoExporter.exportText`）。 */
    fun export(
        memos: List<ScheduleMemoEntity>,
        now: Instant = Instant.now(),
        zone: ZoneId = scheduleCampusZone,
    ): String {
        val active = memos.filter { it.trashedAt == null }
            .sortedByDescending { it.createdAt }
        val formatter = java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
        val builder = StringBuilder()
        builder.append("MyLeafy 随记导出\n")
        builder.append("导出时间：").append(formatter.format(now.atZone(zone))).append('\n')
        builder.append("随记数量：").append(active.size).append('\n')
        active.forEach { memo ->
            builder.append('\n').append(separator).append('\n')
            builder.append("创建时间：").append(formatter.format(createdDateTime(memo, zone))).append('\n')
            if (memo.kind == "article" && !memo.title.isNullOrBlank()) {
                builder.append("标题：").append(memo.title).append('\n')
            }
            val tags = ScheduleMemoTagParser.decode(memo.tags)
            if (tags.isNotEmpty()) {
                builder.append("标签：").append(tags.joinToString(" ") { "#$it" }).append('\n')
            }
            builder.append('\n').append(memo.body).append('\n')
        }
        return builder.toString()
    }
}

internal fun createdDateTime(memo: ScheduleMemoEntity, zone: ZoneId = scheduleCampusZone) =
    Instant.ofEpochMilli(memo.createdAt).atZone(zone)

internal fun createdDate(memo: ScheduleMemoEntity, zone: ZoneId = scheduleCampusZone) =
    createdDateTime(memo, zone).toLocalDate()

private fun dayRange(start: LocalDate, endInclusive: LocalDate): List<LocalDate> {
    val days = ArrayList<LocalDate>()
    var cursor = start
    while (!cursor.isAfter(endInclusive)) {
        days += cursor
        cursor = cursor.plusDays(1)
    }
    return days
}
