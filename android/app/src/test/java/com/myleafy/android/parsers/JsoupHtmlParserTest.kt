package com.myleafy.android.parsers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 解析回归测试：与 iOS `leafyTests` 共用 contracts/jwxt 的同一组 Fixture。
 * 期望结果见 contracts/jwxt/expected/expected.json。
 */
class JsoupHtmlParserTest {

    private val parser = JsoupHtmlParser()

    @Test
    fun parsesKbcontentDivTimetable() {
        val records = parser.parseTimetable(fixture("timetable_kbcontent_div.html"))
        assertEquals(2, records.size)
        val names = records.map { it.courseName }.sorted()
        assertEquals(listOf("数据结构", "森林生态学"), names)

        val forest = records.first { it.courseName == "森林生态学" }
        assertEquals("王老师", forest.teacher)
        assertEquals("二教", forest.location)
        assertEquals("205", forest.room)
        assertEquals(1, forest.dayOfWeek)
        assertEquals((1..18).toList(), forest.weeks)
        assertEquals(listOf(1, 2), forest.duration)

        val ds = records.first { it.courseName == "数据结构" }
        assertEquals("二教", ds.location)
        assertEquals("301", ds.room)
        assertEquals(3, ds.dayOfWeek)
        assertEquals((2..16).toList(), ds.weeks)
        assertEquals(listOf(3, 4), ds.duration)
    }

    @Test
    fun recognizesEmptyTimetableAsEmptyList() {
        assertTrue(parser.parseTimetable(fixture("timetable_empty_kbcontent.html")).isEmpty())
    }

    @Test
    fun parsesStrongSystemTimetableWithOpaqueContentIds() {
        val html = """
            <html><body><table id="kbtable">
              <tr><th></th><th>星期一</th><th>星期二</th></tr>
              <tr><th>第一二节</th>
                <td>
                  <div class="kbcontent1">森林生态学<br><font>1-2(周)</font><br><font>二教205</font></div>
                  <div id="opaque-1-1-2" class="kbcontent">森林生态学(必修)<br><font>王老师</font><br><font>1-2(周)</font><br><font>二教205</font></div>
                </td>
                <td><div class="kbcontent1"></div><div id="opaque-1-2-2" class="kbcontent"></div></td>
              </tr>
              <tr><th>实验实习安排</th><td colspan="2"></td></tr>
            </table></body></html>
        """.trimIndent()

        val records = parser.parseTimetable(html)

        assertEquals(1, records.size)
        assertEquals("森林生态学(必修)", records.single().courseName)
        assertEquals("王老师", records.single().teacher)
        assertEquals(1, records.single().dayOfWeek)
        assertEquals(listOf(1, 2), records.single().weeks)
        assertEquals(listOf(1, 2), records.single().duration)
    }

    @Test
    fun recognizesPublishedEmptyTimetableMessage() {
        val html = """
            <html><body>
              <table id="kbtable"><tr><th></th><th>星期一</th></tr><tr><th>实验实习安排</th><td></td></tr></table>
              <script>alert('课表暂未公布，不能查看课表！');</script>
            </body></html>
        """.trimIndent()

        assertTrue(parser.parseTimetable(html).isEmpty())
    }

    @Test
    fun recognizesEmptyGraduateTimetableAsEmptyList() {
        assertTrue(parser.parseTimetable(fixture("timetable_graduate_empty.json")).isEmpty())
    }

    @Test
    fun unknownPageThrowsTableNotFound() {
        val error = assertThrows(HtmlParseError::class.java) {
            parser.parseTimetable(fixture("timetable_unrecognized_page.html"))
        }
        assertEquals(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, error.kind)
    }

    @Test
    fun malformedContentThrowsRowsUnparseable() {
        val error = assertThrows(HtmlParseError::class.java) {
            parser.parseTimetable(fixture("timetable_malformed_content.html"))
        }
        assertEquals(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, error.kind)
    }

    @Test
    fun skipsOutOfRangeDayIds() {
        val records = parser.parseTimetable(fixture("timetable_out_of_range_days.html"))
        assertEquals(listOf("有效课程"), records.map { it.courseName })
        assertEquals(1, records.first().dayOfWeek)
        assertEquals(listOf(1, 2), records.first().duration)
    }

    @Test
    fun recognizesEmptyGradesTable() {
        assertTrue(parser.parseGrades(fixture("grades_empty_table.html")).isEmpty())
    }

    @Test
    fun parsesGradesWithRows() {
        val grades = parser.parseGrades(fixture("grades_with_rows.html"))
        assertEquals(2, grades.size)

        val ds = grades.first { it.courseName == "数据结构" }
        assertEquals("2025-2026-2", ds.term)
        assertEquals("92", ds.score)
        assertEquals("3.5", ds.credit)
        assertEquals("必修 · 专业核心", ds.type)

        val math = grades.first { it.courseName == "高等数学 A" }
        assertEquals("88", math.score)
        assertEquals("5", math.credit)
        assertEquals("必修 · 公共基础", math.type)
    }

    @Test
    fun parsesOfficialGradeRankingsAndSummary() {
        val html = """
            <html><body>
              <p>平均学分绩点：3.42，学分积为 271.5，班级排名第 8 名，专业排名第 20 名，专业总人数 120 人。</p>
              <table id="rankings">
                <tr><th>学年</th><th>学分积</th><th>班级排名</th><th>专业排名</th></tr>
                <tr><td>2025-2026</td><td>82.5</td><td>5</td><td>16</td></tr>
              </table>
            </body></html>
        """.trimIndent()

        val rankings = parser.parseGradeRankings(html)
        val summary = parser.parseGradeSummary(html)

        assertEquals(4, rankings.size)
        assertEquals(8, rankings.first { it.term == "全部学期" && it.rankingRange == "班级排名" }.rank)
        assertEquals(120, rankings.first { it.term == "全部学期" && it.rankingRange == "专业排名" }.totalCount)
        assertEquals(3.42, summary.officialGpa)
        assertEquals(271.5, summary.officialCreditPoint)
    }

    @Test
    fun parsesExamBackendShape() {
        val exams = parser.parseExams(fixture("exams_backend_shape.html"))
        assertEquals(1, exams.size)
        val exam = exams.first()
        assertEquals(1, exam.id)
        assertEquals("DS-001", exam.courseId)
        assertEquals("数据结构", exam.name)
        assertEquals("2026-06-20", exam.date)
        assertEquals("09:00", exam.start)
        assertEquals("11:00", exam.end)
        assertEquals("二教 205", exam.location)
    }

    @Test
    fun parsesExamSplitDateAndTimeColumns() {
        val exams = parser.parseExams(fixture("exams_split_columns.html"))
        assertEquals(1, exams.size)
        val exam = exams.first()
        assertEquals(2, exam.id)
        assertEquals("MATH-001", exam.courseId)
        assertEquals("高等数学 A", exam.name)
        assertEquals("2026-06-21", exam.date)
        assertEquals("14:00", exam.start)
        assertEquals("16:00", exam.end)
        assertEquals("主楼 112", exam.location)
    }

    @Test
    fun parsesEmptyClassroomsWithBuildingAliases() {
        val rooms = parser.parseEmptyClassrooms(fixture("empty_classrooms.html"))
        assertEquals(3, rooms.size)
        assertEquals(EmptyClassroom(building = "学研A座", room = "0304"), rooms[0])
        assertEquals(EmptyClassroom(building = "学研B座", room = "0405"), rooms[1])
        assertEquals(EmptyClassroom(building = "二教", room = "608"), rooms[2])
    }

    private fun fixture(name: String): String {
        val stream = checkNotNull(javaClass.classLoader?.getResourceAsStream("jwxt/fixtures/$name")) {
            "Fixture 缺失: jwxt/fixtures/$name"
        }
        return stream.bufferedReader().readText()
    }
}
