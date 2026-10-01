package com.myleafy.android.features.campus

import com.myleafy.android.core.data.local.*
import com.myleafy.android.features.timetable.domain.*
import com.myleafy.android.parsers.*
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate

class CampusParityRulesTest {
    private fun program(vararg requirements: ParsedGraduationCreditRequirement) = ParsedTrainingProgram("方案", emptyList(), emptyList(), requirements.toList())
    private fun summary(total: Double?) = GradeSummaryEntity("test", officialGpa = null, officialWeightedAverage = null, officialCreditPoint = null, totalCredits = total, publicElectiveCredits = 0.0)
    private val grades = listOf(GradeEntity("test", "old", "2025-2026-1", "数学", "3", "50", "必修", courseCode = "M"), GradeEntity("test", "new", "2025-2026-2", "数学", "3", "90", "必修", courseCode = "M"), GradeEntity("test", "failed", "2025-2026-2", "物理", "2", "不及格", "必修"))
    @Test fun officialZeroAndUnknownRemainDistinct() {
        val result = GraduationProgress.calculate(program(ParsedGraduationCreditRequirement("总学分", 167.0, true), ParsedGraduationCreditRequirement("公共选修", 8.5, false), ParsedGraduationCreditRequirement("专业核心课", 15.0, false)), grades, summary(0.0))
        assertTrue(result.official); assertEquals(0.0, result.completed, 0.0); assertEquals(167.0, result.remaining!!, 0.0)
        assertEquals(0.0, result.categories.first().completed!!, 0.0); assertNull(result.categories.last().completed)
    }
    @Test fun missingTotalDoesNotAddOverlapsAndRetakesCountOnce() {
        val result = GraduationProgress.calculate(program(ParsedGraduationCreditRequirement("必修", 100.0, false), ParsedGraduationCreditRequirement("专业核心课", 20.0, false)), grades, null)
        assertFalse(result.official); assertEquals(3.0, result.completed, 0.0); assertNull(result.required); assertNull(result.remaining)
    }
    @Test fun categoryAggregateDoesNotDoubleCountCourseRows() {
        val result = GraduationProgress.calculate(program(ParsedGraduationCreditRequirement("总学分", 167.0, true), ParsedGraduationCreditRequirement("专业选修", 20.0, false), ParsedGraduationCreditRequirement("专业选修", 3.0, false, "A", isAggregate = false)), grades, summary(200.0))
        assertEquals(167.0, result.required!!, 0.0); assertEquals(20.0, result.categories.single().required, 0.0); assertEquals(0.0, result.remaining!!, 0.0)
    }
    @Test fun officialTableRetainsZeroBucketsAndRawFields() {
        val result = JsoupHtmlParser().parseGradeSummary("""<p>平均学分绩点(GPA)：3.2</p><table><tr><th rowspan="2">所得学分</th><th rowspan="2">必修学分</th><th colspan="3">专业选修学分</th><th colspan="2">公共选修学分</th></tr><tr><th>总计</th><th>本专业</th><th>外专业</th><th>总计</th><th>美育</th></tr><tr><td>140</td><td>120</td><td>12</td><td>10</td><td>2</td><td>0</td><td></td></tr></table>""")
        assertEquals(140.0,result.totalCredits!!,0.0); assertEquals(120.0,result.requiredCredits!!,0.0); assertEquals(10.0,result.professionalMajorElectiveCredits!!,0.0); assertEquals(2.0,result.professionalCrossMajorElectiveCredits!!,0.0)
        assertEquals(0.0,result.publicElectiveCredits!!,0.0); assertEquals(0.0,result.publicElectiveBuckets.getValue("美育"),0.0); assertEquals("140",result.rawFields["所得学分"])
    }
    @Test fun invalidRecognizedCreditTableFails() {
        assertThrows(HtmlParseError::class.java) { JsoupHtmlParser().parseGradeSummary("<table><tr><th>所得学分</th><th>必修学分</th></tr><tr><td>140</td><td>待确认</td></tr></table>") }
    }
    @Test fun explicitTotalRowDoesNotUsePlannedTotalOrCategorySubtotals() {
        val parsed = JsoupHtmlParser().parseTrainingProgram("""<p>本科培养方案</p><table><tr><th>类别</th><th>要求学分</th><th>计划学分</th></tr><tr><td>总计</td><td>167</td><td>190</td></tr><tr><td>专业选修</td><td>20</td><td>30</td></tr></table>""")
        val result = GraduationProgress.calculate(parsed, emptyList(), null)
        assertEquals(167.0, result.required!!, 0.0)
        assertEquals(30.0, result.categories.single().required, 0.0)
    }
    @Test fun csvChineseQuotesMultilineReorderedColumnsAndBom() {
        val rows = GuestAcademicCsv.parse("\uFEFFscore,courseName,type,term,credit\r\n85,\"森林,生态\"\"学\n实验\",必修,2026-2027-1,2\r\n", GuestAcademicKind.GRADE)
        assertEquals("森林,生态\"学\n实验", rows.single()[1]); assertEquals("2", rows.single()[2])
    }
    @Test fun invalidCsvReportsRowAndRejectsWholeFile() {
        val failure=assertThrows(IllegalArgumentException::class.java) { GuestAcademicCsv.parse("courseID,name,date,start,end,location\nA,考试A,2026-12-01,09:00,11:00,三教\nB,考试B,2026-12-01,11:00,09:00,三教",GuestAcademicKind.EXAM) }
        assertTrue(failure.message!!.contains("第 3 行")); assertThrows(IllegalArgumentException::class.java) { GuestAcademicCsv.parse("term,courseName,credit,score,type\nA,\"未闭合",GuestAcademicKind.GRADE) }
    }
    @Test fun singleContinuousAndUnknownClassroomCells() {
        val matrix=JsoupHtmlParser().parseClassroomAvailability("<table id='dataList'><tr><th>星期一</th></tr><tr><td>教室</td><td tdvalue='0102'></td><td tdvalue='0304'></td></tr><tr jsbh='A'><td>A0304(20/10)</td><td>◆Ｌ</td><td></td></tr><tr jsbh='B'><td>B0405(20/10)</td><td></td><td>?</td></tr></table>")
        assertEquals(ClassroomStatus.OCCUPIED,matrix.rows.first().slots.first().status); assertEquals("0405",matrix.available(1,2).single().room); assertEquals(ClassroomStatus.UNKNOWN,matrix.rows.last().slots.last().status)
        assertThrows(IllegalStateException::class.java) { matrix.available(1,4) }; assertThrows(IllegalStateException::class.java) { matrix.available(1,12) }
    }
    @Test fun csvUsesPhysicalLineNumbersAndValidatesCreditAndTerm() {
        val header = "term,courseName,credit,score,type\r\n"
        val failure = assertThrows(IllegalArgumentException::class.java) {
            GuestAcademicCsv.parse(header + "\r\n2026,\"森林\r\n生态\",2,85,必修\r\n2026,错误学分,NaN,85,必修", GuestAcademicKind.GRADE)
        }
        assertTrue(failure.message!!.contains("第 5 行"))
        listOf("", "-1", "Infinity", "未知").forEach { credit ->
            assertThrows(IllegalArgumentException::class.java) { GuestAcademicCsv.validate(GuestAcademicKind.GRADE, listOf("2026", "课程", credit, "通过", "")) }
        }
        assertThrows(IllegalArgumentException::class.java) { GuestAcademicCsv.validate(GuestAcademicKind.GRADE, listOf("", "课程", "0", "通过", "")) }
        assertEquals("0", GuestAcademicCsv.parse("\uFEFF\"term\",courseName,credit,score,type\n2026,课程,0,通过,",GuestAcademicKind.GRADE).single()[2])
    }
    @Test fun runPeriodsUseRealEndExcludedWeeksAndDistinctDates() {
        val config=SemesterRuntimeConfig.builtIn; val settings=SunshineRunSettingsEntity("test",weeksPerPeriod=2,excludedWeeks="3,4,5,17")
        fun record(date:LocalDate)=SunshineRunRecordEntity(date.toString(),"test",date.toEpochDay(),99,100,1,1)
        val records=listOf(record(config.semesterStartDate),record(config.semesterStartDate),record(config.semesterStartDate.plusWeeks(2)),record(SunshineRunPlanner.semesterEnd(config)),record(SunshineRunPlanner.semesterEnd(config).plusDays(1)))
        val periods=SunshineRunPlanner.periods(records,settings,config)
        assertEquals(1,periods.first().count); assertEquals(2,periods.sumOf { it.count }); assertEquals(SunshineRunPlanner.semesterEnd(config),periods.last().end)
        assertNull(SunshineRunPlanner.period(config.semesterStartDate.plusWeeks(2),periods,config)); assertNull(SunshineRunPlanner.period(config.semesterStartDate.minusDays(1),periods,config))
        assertNotNull(SunshineRunPlanner.period(config.semesterStartDate.plusWeeks(2),SunshineRunPlanner.periods(records,settings.copy(skipsExcludedWeeks=false),config),config))
    }
    @Test fun fitnessMinutesSecondsAndCustomUnits() {
        val record=FitnessTestRecordEntity("id","test",1,"1000米",245.0,"分秒","",1,1)
        assertEquals("4分5秒",fitnessValue(record)); assertEquals("245 次",fitnessValue(record.copy(item="自定义",unit="次")))
        assertEquals("4分6秒", fitnessValue(record.copy(value=245.6)))
    }
}
