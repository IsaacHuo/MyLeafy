package com.myleafy.android.parsers

/**
 * 教务 HTML 解析器接口（阶段 2 由 jsoup 实现，选择器语法与 iOS SwiftSoup 一致）。
 *
 * 契约要点（见 docs/engineering/android-migration.md 教务协议记录）：
 * - 解析器不做页面导航、持久化或用户提示；
 * - 必须区分“可信空结果”与“非空但无法解析”，两者不得混用；
 * - 输入为已解码文本（UTF-8 优先，失败回退 GB18030，由网络层负责解码）。
 */
interface HtmlParser {

    /** 解析课表页面。未知页面抛 [HtmlParseError]；空数据返回空列表。 */
    fun parseTimetable(html: String): List<ParsedCourseRecord>

    /** 解析成绩页面。 */
    fun parseGrades(html: String): List<ParsedGradeRecord>

    /** 解析成绩页中的学校官方班级/专业排名。无排名结构时抛出解析错误。 */
    fun parseGradeRankings(html: String): List<ParsedGradeRanking>

    /** 解析成绩页中的学校官方 GPA、学分积与均分。 */
    fun parseGradeSummary(html: String): ParsedGradeSummary

    /** 解析考试安排页面。 */
    fun parseExams(html: String): List<ParsedExamRecord>

    /** 解析空教室页面（空闲教室，占用行会被跳过）。 */
    fun parseEmptyClassrooms(html: String): List<EmptyClassroom>
}

/** 课表课程记录（解析器中间产物，不直接持久化）。 */
data class ParsedCourseRecord(
    val courseName: String,
    val teacher: String,
    val classInfo: String,
    val room: String,
    val location: String,
    val dayOfWeek: Int,
    val weeks: List<Int>,
    val duration: List<Int>,
)

/** 成绩记录；credit/score 保持原始字符串（与 iOS `Grade` 一致，避免数值化丢失）。 */
data class ParsedGradeRecord(
    val term: String,
    val courseName: String,
    val credit: String,
    val score: String,
    val type: String,
)

data class ParsedGradeRanking(
    val term: String,
    val rankingRange: String,
    val rank: Int,
    val totalCount: Int?,
    val metricText: String,
)

data class ParsedGradeSummary(
    val officialGpa: Double?,
    val officialWeightedAverage: Double?,
    val officialCreditPoint: Double?,
)

/** 考试安排记录。 */
data class ParsedExamRecord(
    val id: Int,
    val courseId: String,
    val name: String,
    val date: String,
    val start: String,
    val end: String,
    val location: String,
)

/** 空教室。 */
data class EmptyClassroom(
    val building: String,
    val room: String,
)

class HtmlParseError(val kind: ParseErrorKind, detail: String) : Exception(detail) {
    enum class ParseErrorKind {
        /** 未知页面，缺少目标结构。 */
        TABLE_NOT_FOUND,

        /** 页面结构存在但内容无法解析。 */
        TABLE_ROWS_UNPARSEABLE,
    }
}
