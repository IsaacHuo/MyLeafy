package com.myleafy.android.features.schedule

import com.myleafy.android.core.network.TimetableRefreshResult
import org.junit.Assert.assertEquals
import org.junit.Test

class ScheduleMemoTagMergeTest {

    @Test
    fun bodyTagsAreMergedAndDeduplicatedAgainstExplicitTags() {
        val merged = mergeMemoTags(
            explicitTags = listOf("数据结构", " 复习 "),
            body = "今天看了 #数据结构 和 #算法，还复习了 #复习",
        )

        assertEquals(listOf("数据结构", "复习", "算法"), merged)
    }

    @Test
    fun explicitTagWinsOverBodySpelling() {
        val merged = mergeMemoTags(
            explicitTags = listOf("DataStructure"),
            body = "#datastructure #算法",
        )

        assertEquals(listOf("DataStructure", "算法"), merged)
    }
}

class TimetableRefreshResultTest {

    @Test
    fun retainedEmptyTimetableExplainsThatLocalDataWasKept() {
        val result = TimetableRefreshResult(
            courseCount = 6,
            arrangementCount = 12,
            changed = false,
            retainedExisting = true,
        )

        assertEquals(
            "学校本次未返回课程，已保留本地课表；备注、提醒和个人日程保持不变。",
            result.message,
        )
    }

    @Test
    fun unchangedResultReportsCountsWithoutClaimingAnUpdate() {
        val result = TimetableRefreshResult(courseCount = 6, arrangementCount = 12, changed = false)

        assertEquals("同步完成，课表已是最新，共 6 门课程、12 条安排。", result.message)
    }
}
