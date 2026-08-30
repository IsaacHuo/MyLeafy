package com.myleafy.android.features.community

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CommunityFeedSelectionTest {
    @Test
    fun latestSelectionKeepsCategoryAndNormalizedSearch() {
        val query = CommunityFeedSelection(category = "学习交流")
            .toQuery(campusId = "bjfu", search = "  高数  ")

        assertEquals("bjfu", query.campus_id)
        assertEquals("学习交流", query.category)
        assertEquals("高数", query.search)
        assertNull(query.mode)
        assertNull(query.days)
    }

    @Test
    fun hotSelectionUsesSevenDaysAndDropsUnsupportedFilters() {
        val query = CommunityFeedSelection(
            mode = CommunityFeedMode.HOT,
            category = "学习交流",
        ).toQuery(campusId = "bjfu", search = "高数")

        assertEquals("hot", query.mode)
        assertEquals(7, query.days)
        assertNull(query.category)
        assertNull(query.search)
    }
}
