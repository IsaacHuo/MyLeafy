package com.myleafy.android.core.network.okhttp

import com.myleafy.android.core.network.SchoolNetworkError
import okhttp3.HttpUrl.Companion.toHttpUrl
import okio.Buffer
import org.junit.Assert.*
import org.junit.Test

class TimetablePageResolverTest {
    private val origin = "https://school.example/".toHttpUrl()
    @Test fun `form keeps required fields and selects requested semester`() {
        val html = """<form action="/jsxsd/xskb/query" method="POST">
          <input name="token" value="school-token"><input type="submit" name="submit" value="查询">
          <select name="xnxq01id"><option selected value="old">old</option><option value="2026-2027-1">new</option></select>
        </form>"""
        val request = TimetablePageResolver.candidates(html, origin, origin, "2026-2027-1").single()
        assertEquals("POST", request.method)
        val body = Buffer().also { request.body!!.writeTo(it) }.readUtf8()
        assertTrue(body.contains("token=school-token"))
        assertTrue(body.contains("xnxq01id=2026-2027-1"))
        assertFalse(body.contains("submit="))
    }
    @Test fun `wrong or missing semester cannot replace cached timetable`() {
        assertThrows(SchoolNetworkError.TimetableSemesterMismatch::class.java) {
            TimetablePageResolver.verifySemester("<table id='kbtable'></table>", "2026-2027-1")
        }
        assertThrows(SchoolNetworkError.TimetableSemesterMismatch::class.java) {
            TimetablePageResolver.verifySemester("<input name='xnxq01id' value='2025-2026-2'>", "2026-2027-1")
        }
        TimetablePageResolver.verifySemester("<select name='xnxq01id'><option selected value='2026-2027-1'></option></select>", "2026-2027-1")
    }
    @Test fun `only timetable links on the school origin are followed`() {
        val candidates = TimetablePageResolver.candidates("""
            <a href='https://elsewhere.example/xskb'>课表</a>
            <a href='/logout'>退出</a><iframe src='/jsxsd/xskb/list'></iframe>
        """, origin, origin, "2026-2027-1")
        assertEquals(1, candidates.size)
        assertEquals("school.example", candidates.single().url.host)
        assertEquals("2026-2027-1", candidates.single().url.queryParameter("xnxq01id"))
    }
}
