package com.myleafy.android.features.schedule

import com.myleafy.android.core.data.local.ScheduleMemoEntity
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleMemoInsightsTest {

    private val zone: ZoneId = scheduleCampusZone

    private fun memo(
        id: String,
        body: String = "内容",
        tags: List<String> = emptyList(),
        createdAt: LocalDate = LocalDate.of(2026, 9, 1),
        kind: String = "quickMemo",
        title: String? = null,
        trashedAt: Long? = null,
    ): ScheduleMemoEntity {
        val millis = createdAt.atTime(10, 0).atZone(zone).toInstant().toEpochMilli()
        return ScheduleMemoEntity(
            scopeKey = "scope",
            id = id,
            body = body,
            kind = kind,
            title = title,
            tags = tags.joinToString("\n"),
            createdAt = millis,
            updatedAt = millis,
            pinnedAt = null,
            trashedAt = trashedAt,
            linkedScheduleKind = null,
            linkedScheduleId = null,
        )
    }

    @Test
    fun tagAggregatorDeduplicatesCaseInsensitivelyAndSorts() {
        val summary = ScheduleMemoTagAggregator.summarize(
            listOf(
                memo("1", tags = listOf("学习", "Reading")),
                memo("2", tags = listOf("reading", "考试")),
            ),
        )
        assertEquals(3, summary.size)
        assertEquals(listOf("Reading", "学习", "考试"), summary.map { it.name })
        assertEquals(2, summary.first { it.name == "Reading" }.count)
    }

    @Test
    fun tagParserExtractsInlineHashtags() {
        val tags = ScheduleMemoTagParser.tagsIn("今天复习 #数据结构 和 #英语/阅读")
        assertEquals(listOf("数据结构", "英语/阅读"), tags)
    }

    @Test
    fun statisticsComputedForSelectedYear() {
        val memos = listOf(
            memo("1", createdAt = LocalDate.of(2026, 9, 1)),
            memo("2", createdAt = LocalDate.of(2026, 9, 1)),
            memo("3", createdAt = LocalDate.of(2026, 9, 2)),
            memo("trashed", createdAt = LocalDate.of(2026, 9, 3), trashedAt = 1L),
        )
        val statistics = ScheduleMemoStatisticsCalculator.calculate(
            memos = memos,
            selectedYear = 2026,
            now = LocalDate.of(2026, 9, 10),
            zone = zone,
        )
        assertEquals(3, statistics.memoCount)
        assertEquals(2, statistics.recordingDayCount)
        assertEquals(3, statistics.selectedYearMonths.first { it.month == 9 }.memoCount)
        assertEquals(2, statistics.selectedYearMonths.first { it.month == 9 }.recordingDayCount)
        assertEquals(2, statistics.peakMemoCount)
        assertEquals(LocalDate.of(2026, 9, 1), statistics.peakDate)
        // 2026-09-01 是周二（index 1），2026-09-02 是周三（index 2），周一为 0。
        assertEquals(2, statistics.weekdayDistribution[1])
        assertEquals(1, statistics.weekdayDistribution[2])
        assertEquals(0, statistics.currentStreak)
        assertEquals(2, statistics.longestStreak)
    }

    @Test
    fun reviewEnginePrefersAnniversary() {
        val memos = listOf(
            memo("old", createdAt = LocalDate.of(2024, 9, 15)),
            memo("other", createdAt = LocalDate.of(2025, 1, 1)),
            memo("today", createdAt = LocalDate.of(2026, 9, 15)),
        )
        val selection = ScheduleMemoReviewEngine.select(
            memos = memos,
            today = LocalDate.of(2026, 9, 15),
            page = 0,
            zone = zone,
        )
        assertEquals("old", selection.first().id)
        assertTrue(selection.none { it.id == "today" })
    }

    @Test
    fun textExportExcludesTrashedAndIncludesTags() {
        val text = ScheduleMemoTextExporter.export(
            memos = listOf(
                memo("1", body = "复习", tags = listOf("学习"), createdAt = LocalDate.of(2026, 9, 1)),
                memo("2", body = "丢弃", createdAt = LocalDate.of(2026, 9, 2), trashedAt = 1L),
            ),
            now = Instant.parse("2026-09-10T00:00:00Z"),
            zone = zone,
        )
        assertTrue(text.contains("MyLeafy 随记导出"))
        assertTrue(text.contains("复习"))
        assertTrue(text.contains("标签：#学习"))
        assertTrue(!text.contains("丢弃"))
    }
}
