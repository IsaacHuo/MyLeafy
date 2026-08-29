package com.myleafy.android.parsers

import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode
import java.time.LocalDate

/**
 * jsoup 实现的教务 HTML 解析器。
 *
 * 行为与 iOS `HTMLParser.swift` 逐项一致（选择器、单元格索引、正则、可信空判定）。
 * 解析器不做页面导航、持久化或用户提示；输入为已解码文本（UTF-8/GB18030 由网络层完成）。
 */
class JsoupHtmlParser : HtmlParser {

    // MARK: - 课表

    override fun parseTimetable(html: String): List<ParsedCourseRecord> {
        val trimmed = html.trim()
        if (trimmed.startsWith("{") && trimmed.contains("\"rows\"")) {
            return parseGraduateTimetableResult(trimmed)
        }

        val document = Jsoup.parse(html)

        val contentElements = document.select("[id^=kbcontent_], .kbcontent")
        val placedContentElements = contentElements.filter { parseDayAndDuration(it) != null }
        if (placedContentElements.isNotEmpty()) {
            val records = parseTimetableContentElements(placedContentElements)
            if (records.isNotEmpty()) return records
            val containsCourseContent = placedContentElements.any { it.text().trim().isNotEmpty() }
            if (containsCourseContent) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "课表")
            return emptyList()
        }

        val timetableTable = document.select("#kbtable").firstOrNull()
        if (timetableTable != null) {
            if (isExplicitlyEmptyTimetable(html)) return emptyList()
            val records = parseTimetableTable(timetableTable)
            if (records.isNotEmpty()) return records
            val rows = timetableTable.select("tr")
            if (rows.size <= 2) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "课表")
            val courseBlocks = rows.subList(1, rows.size - 1).flatMap { row ->
                val divs = row.select("div")
                (1 until divs.size step 2).map { divs[it] }
            }
            val containsCourseContent = courseBlocks.any { it.text().trim().isNotEmpty() }
            if (containsCourseContent) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "课表")
            return emptyList()
        }

        if (contentElements.any { it.text().trim().isNotEmpty() }) {
            throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "课表")
        }

        throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "课表")
    }

    private fun isExplicitlyEmptyTimetable(pageText: String): Boolean {
        val compact = pageText.replace(Regex("\\s+"), "")
        return explicitEmptyTimetableMarkers.any(compact::contains)
    }

    /**
     * 研究生课表 JSON。M2.3 仅处理可信空（`"rows":[]`）；
     * 非空研究生课表在研究生（RSA+AES）里程碑接入完整解析。
     */
    private fun parseGraduateTimetableResult(json: String): List<ParsedCourseRecord> {
        val emptyRows = json.contains("\"rows\":[]") || json.contains("\"rows\": []")
        if (emptyRows) return emptyList()
        throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "研究生课表（完整解析后续接入）")
    }

    private fun parseTimetableContentElements(elements: List<Element>): List<ParsedCourseRecord> {
        val weekly = makeEmptyWeeklyMatrix()
        for (element in elements) {
            val placement = parseDayAndDuration(element) ?: continue
            for ((data, weeks) in parseStudentBlock(element, placement.second)) {
                if (data.courseName.isEmpty() || weeks.isEmpty()) continue
                for (week in weeks) {
                    if (week !in 1..totalWeeks) continue
                    appendToWeeklyCell(weekly, week, placement.first, data, weeks)
                }
            }
        }
        return buildCourseRecords(weekly)
    }

    private fun parseTimetableTable(table: Element): List<ParsedCourseRecord> {
        val allRows = table.select("tr")
        if (allRows.size <= 2) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "课表")
        val rows = allRows.subList(1, allRows.size - 1)

        val weekly = makeEmptyWeeklyMatrix()
        for ((rowIndex, row) in rows.withIndex()) {
            if (rowIndex !in durationSlots.indices) break
            val allDivs = row.select("div")
            val blocks = (1 until allDivs.size step 2).map { allDivs[it] }
            val duration = durationSlots[rowIndex]
            for ((dayIndex, block) in blocks.withIndex()) {
                if (dayIndex >= totalDays) continue
                for ((data, weeks) in parseStudentBlock(block, duration)) {
                    if (data.courseName.isEmpty() || weeks.isEmpty()) continue
                    for (week in weeks) {
                        if (week !in 1..totalWeeks) continue
                        appendToWeeklyCell(weekly, week, dayIndex + 1, data, weeks)
                    }
                }
            }
        }
        return buildCourseRecords(weekly)
    }

    private fun appendToWeeklyCell(
        weekly: List<MutableList<MutableList<Pair<CourseData, List<Int>>>>>,
        week: Int,
        dayOfWeek: Int,
        data: CourseData,
        weeks: List<Int>,
    ) {
        val cell = weekly[week - 1][dayOfWeek - 1]
        val previous = cell.lastOrNull()
        when {
            previous != null && compareCourseData(previous.first, data) == 1 -> {
                val merged = previous.first.copy(duration = previous.first.duration + data.duration)
                cell[cell.size - 1] = merged to previous.second
            }
            previous == null || compareCourseData(previous.first, data) != 2 -> {
                cell.add(data to weeks)
            }
        }
    }

    private fun buildCourseRecords(weekly: List<MutableList<MutableList<Pair<CourseData, List<Int>>>>>): List<ParsedCourseRecord> {
        val unique = mutableMapOf<String, ParsedCourseRecord>()
        for ((weekIndex, weekData) in weekly.withIndex()) {
            val weekNumber = weekIndex + 1
            for ((dayIndex, dayCourses) in weekData.withIndex()) {
                val dayOfWeek = dayIndex + 1
                for ((data, _) in dayCourses) {
                    val key = "${data.courseName}|$dayOfWeek|${data.duration}|${data.room}|${data.location}"
                    val existing = unique[key]
                    if (existing != null) {
                        if (!existing.weeks.contains(weekNumber)) {
                            unique[key] = existing.copy(weeks = (existing.weeks + weekNumber).sorted())
                        }
                    } else {
                        unique[key] = makeCourseRecord(data, dayOfWeek, listOf(weekNumber))
                    }
                }
            }
        }
        return unique.values.toList()
    }

    private fun makeCourseRecord(data: CourseData, dayOfWeek: Int, weeks: List<Int>): ParsedCourseRecord =
        ParsedCourseRecord(
            courseName = data.courseName,
            teacher = data.teacher.ifEmpty { "未知" },
            classInfo = data.classInfo,
            room = data.room.ifEmpty { "未知" },
            location = data.location.ifEmpty { data.room },
            dayOfWeek = dayOfWeek,
            weeks = weeks.sorted(),
            duration = data.duration,
        )

    private fun compareCourseData(prev: CourseData, curr: CourseData): Int {
        if (prev.courseName == curr.courseName &&
            prev.location == curr.location &&
            prev.room == curr.room &&
            prev.classInfo == curr.classInfo
        ) {
            val last = prev.duration.lastOrNull()
            val first = curr.duration.firstOrNull()
            if (last != null && first != null && last + 1 == first) return 1
            if (prev.duration.sum() == curr.duration.sum()) return 2
        }
        return 0
    }

    private fun makeEmptyWeeklyMatrix(): List<MutableList<MutableList<Pair<CourseData, List<Int>>>>> =
        List(totalWeeks) { MutableList(totalDays) { mutableListOf<Pair<CourseData, List<Int>>>() } }

    private fun parseDayAndDuration(element: Element): Pair<Int, List<Int>>? {
        val id = element.attr("id").trim()
        if (id.isEmpty()) return null
        val parts = id.split("_")
        if (parts.size < 3 || parts[0] != "kbcontent") return null
        val dayOfWeek = parts[1].toIntOrNull() ?: return null
        val periodIndex = parts[2].toIntOrNull() ?: return null
        if (dayOfWeek !in 1..totalDays) return null

        val explicit = parseDuration(element.text())
        if (explicit.isNotEmpty()) return dayOfWeek to explicit
        if (periodIndex - 1 in durationSlots.indices) return dayOfWeek to durationSlots[periodIndex - 1]
        return dayOfWeek to listOf(periodIndex)
    }

    private fun parseStudentBlock(block: Element, duration: List<Int>): List<Pair<CourseData, List<Int>>> {
        val extracted = extractTexts(block)
        val chunks = mutableListOf<MutableList<String>>()
        var current = mutableListOf<String>()
        for (item in extracted) {
            when {
                item.contains("---") || item == "###HR###" -> {
                    if (current.isNotEmpty()) {
                        chunks.add(current)
                        current = mutableListOf()
                    }
                }
                item == "#BR#" -> Unit
                else -> current.add(item)
            }
        }
        if (current.isNotEmpty()) chunks.add(current)
        return chunks.map { parseStudentClassBlock(it, duration) }
    }

    private fun extractTexts(node: Node): List<String> {
        val results = mutableListOf<String>()
        for (child in node.childNodes()) {
            when (child) {
                is TextNode -> {
                    val text = child.text().trim()
                    if (text.isNotEmpty() && text != "\u00A0") results.add(text)
                }
                is Element -> when (child.tagName().lowercase()) {
                    "br" -> results.add("#BR#")
                    "hr" -> results.add("###HR###")
                    else -> results.addAll(extractTexts(child))
                }
            }
        }
        return results
    }

    private fun parseStudentClassBlock(items: List<String>, duration: List<Int>): Pair<CourseData, List<Int>> {
        var name = ""
        var teacher = ""
        var weeksString = ""
        var room = ""
        var location = ""

        for ((index, item) in items.withIndex()) {
            val firstChar = item.firstOrNull() ?: continue
            when {
                index == 0 -> name = item
                index == 1 && !firstChar.isDigit() -> teacher = item
                item.contains("节") && firstChar.isDigit() -> {
                    if (weeksString.isEmpty() || item.contains("周")) weeksString = item
                }
                firstChar.isDigit() || item.contains("周") -> {
                    if (weeksString.isEmpty() || (!weeksString.contains("周") && item.contains("周"))) {
                        weeksString = item
                    } else {
                        val parsed = parseClassroomBuilding(item)
                        if (room.isEmpty()) {
                            room = parsed.first
                            location = parsed.second
                        }
                    }
                }
                else -> {
                    val parsed = parseClassroomBuilding(item)
                    room = parsed.first
                    location = parsed.second
                }
            }
        }

        val data = CourseData(
            courseName = name,
            teacher = teacher,
            classInfo = "",
            room = room,
            location = location,
            duration = duration,
        )
        return data to parseWeeks(weeksString)
    }

    private fun parseClassroomBuilding(loc: String): Pair<String, String> {
        val normalized = loc.trim().replace(Regex("\\s+"), "")
        val firstDigitIndex = normalized.indexOfFirst { it.code in 48..57 }
        if (firstDigitIndex < 0) return normalized to normalized
        val prefix = normalized.substring(0, firstDigitIndex)
        val room = normalized.substring(firstDigitIndex)
        val location = locationMap[prefix] ?: prefix
        return room to location
    }

    private fun parseWeeks(weeksString: String): List<Int> {
        val compact = weeksString.replace(" ", "")
        val oddOnly = compact.contains("单")
        val evenOnly = compact.contains("双")
        val weeks = mutableSetOf<Int>()
        for (match in Regex(WEEK_TOKEN).findAll(compact)) {
            val token = match.value
            if (token.contains("-")) {
                val parts = token.split("-")
                if (parts.size == 2) {
                    val start = parts[0].toIntOrNull()
                    val end = parts[1].toIntOrNull()
                    if (start != null && end != null && start <= end) {
                        weeks.addAll(start..end)
                    }
                }
            } else {
                token.toIntOrNull()?.let { weeks.add(it) }
            }
        }
        return weeks
            .filter { week ->
                if (oddOnly) week % 2 == 1
                else if (evenOnly) week % 2 == 0
                else true
            }
            .sorted()
    }

    private fun parseDuration(text: String): List<Int> {
        val compact = text.replace(" ", "")
        val match = Regex(DURATION_PATTERN).find(compact) ?: return emptyList()
        val start = match.groupValues[1].toIntOrNull() ?: return emptyList()
        val end = match.groupValues[2].toIntOrNull()
        return if (end != null && start <= end) (start..end).toList() else listOf(start)
    }

    // MARK: - 成绩

    override fun parseGrades(html: String): List<ParsedGradeRecord> {
        val document = Jsoup.parse(html)
        val gradeTables = candidateDataTables(document).filter { table ->
            val headerText = table.select("th").joinToString(" ") { it.text().trim() }
            headerText.contains("课程名称") &&
                headerText.contains("成绩") &&
                headerText.contains("学分") &&
                (headerText.contains("开课学期") || headerText.contains("课程编号"))
        }
        val gradeTable = gradeTables.firstOrNull() ?: document.select("#dataList").firstOrNull()
            ?: throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "成绩")
        val rows = gradeTable.select("tr")
        val dataRows = rows.filter { it.select("td").isNotEmpty() }
        val parsed = mutableListOf<ParsedGradeRecord>()

        for (row in rows) {
            val tds = row.select("td")
            if (tds.size < 6) continue
            val term = tds[1].text().trim()
            val courseName = tds[3].text().trim()
            var score = tds[4].text().trim()
            val credit = tds[5].text().trim()
            if (term.isEmpty() || courseName.isEmpty() || courseName == "课程名称" || parseCredit(credit) == null) {
                continue
            }
            val courseAttribute = if (tds.size > 7) tds[7].text().trim() else ""
            val courseCategory = if (tds.size > 10) tds[10].text().trim() else ""
            val type = listOf(courseAttribute, courseCategory).filter { it.isNotEmpty() }.joinToString(" · ")

            if (score.isEmpty() || score == " ") {
                score = tds[4].select("a").text().trim()
            }
            if (score.isEmpty() || score == " ") {
                score = tds[4].select("font").text().trim()
            }
            parsed.add(ParsedGradeRecord(term = term, courseName = courseName, credit = credit, score = score, type = type))
        }

        if (dataRows.isNotEmpty() && parsed.isEmpty()) {
            throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "成绩")
        }
        return parsed
    }

    override fun parseGradeRankings(html: String): List<ParsedGradeRanking> {
        val document = Jsoup.parse(html)
        val pageText = document.text().replace(Regex("\\s+"), " ").trim()
        val records = mutableListOf<ParsedGradeRanking>()
        var majorTotal: Int? = null

        Regex(
            "学分积为\\s*([0-9.]+).*?班级排名第\\s*(\\d+)\\s*名.*?" +
                "专业排名第\\s*(\\d+)\\s*名.*?专业总人数\\s*(\\d+)\\s*人",
        ).find(pageText)?.let { match ->
            val creditPoint = match.groupValues[1]
            val classRank = match.groupValues[2].toIntOrNull()
            val majorRank = match.groupValues[3].toIntOrNull()
            majorTotal = match.groupValues[4].toIntOrNull()
            if (classRank != null) {
                records += ParsedGradeRanking(
                    term = "全部学期",
                    rankingRange = "班级排名",
                    rank = classRank,
                    totalCount = null,
                    metricText = "总排名 · 学分积 $creditPoint",
                )
            }
            if (majorRank != null) {
                records += ParsedGradeRanking(
                    term = "全部学期",
                    rankingRange = "专业排名",
                    rank = majorRank,
                    totalCount = majorTotal,
                    metricText = "总排名 · 学分积 $creditPoint",
                )
            }
        }

        for (table in candidateDataTables(document)) {
            val rows = table.select("tr")
            val headerRowIndex = rows.indexOfFirst { row ->
                val header = row.select("th,td").joinToString(" ") { normalizedTableCellText(it) }
                header.contains("学年") && header.contains("学分积") &&
                    header.contains("班级排名") && header.contains("专业排名")
            }
            if (headerRowIndex < 0) continue
            val headers = rows[headerRowIndex].select("th,td").map(::normalizedTableCellText)
            val termIndex = headers.indexOfFirst { it.contains("学年") }
            val creditPointIndex = headers.indexOfFirst { it.contains("学分积") }
            val classRankIndex = headers.indexOfFirst { it.contains("班级排名") }
            val majorRankIndex = headers.indexOfFirst { it.contains("专业排名") }

            for (row in rows.drop(headerRowIndex + 1)) {
                val cells = row.select("td").map(::normalizedTableCellText)
                if (cells.isEmpty() || termIndex !in cells.indices) continue
                val term = cells[termIndex].ifBlank { "未知学年" }
                val creditPoint = cells.getOrNull(creditPointIndex).orEmpty()
                val metric = creditPoint.takeIf(String::isNotBlank)?.let { "学分积 $it" } ?: "学期段排名明细"
                cells.getOrNull(classRankIndex)?.firstInteger()?.let { rank ->
                    records += ParsedGradeRanking(term, "班级排名", rank, null, metric)
                }
                cells.getOrNull(majorRankIndex)?.firstInteger()?.let { rank ->
                    records += ParsedGradeRanking(term, "专业排名", rank, majorTotal, metric)
                }
            }
        }

        if (records.isEmpty()) {
            throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "成绩排名")
        }
        return records.distinctBy { "${it.term}|${it.rankingRange}|${it.rank}|${it.metricText}" }
            .sortedWith(compareByDescending<ParsedGradeRanking> { it.term }.thenBy { it.rankingRange })
    }

    override fun parseGradeSummary(html: String): ParsedGradeSummary {
        val pageText = Jsoup.parse(html).text().replace(Regex("\\s+"), " ").trim()
        val summary = ParsedGradeSummary(
            officialGpa = parseOfficialDecimal(
                pageText,
                labels = listOf("平均学分绩点", "平均绩点", "学分绩点", "绩点", "GPA"),
                maxValue = 5.0,
            ),
            officialWeightedAverage = parseOfficialDecimal(
                pageText,
                labels = listOf("加权平均分", "加权均分", "平均成绩", "平均分"),
                maxValue = 100.0,
            ),
            officialCreditPoint = parseOfficialDecimal(pageText, labels = listOf("学分积"), maxValue = null),
        )
        if (summary.officialGpa == null &&
            summary.officialWeightedAverage == null &&
            summary.officialCreditPoint == null
        ) {
            throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "成绩汇总")
        }
        return summary
    }

    // MARK: - 考试安排

    override fun parseExams(html: String): List<ParsedExamRecord> {
        val document = Jsoup.parse(html)
        val rows = document.select("#dataList tr")
        if (rows.isEmpty()) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "考试安排")

        val headerCells = rows[0].select("th,td").map { normalizedTableCellText(it) }
        val headerIndex = examHeaderIndex(headerCells)
        val parsed = mutableListOf<ParsedExamRecord>()

        for ((offset, row) in rows.drop(1).withIndex()) {
            val cells = row.select("td").map { normalizedTableCellText(it) }
            if (cells.isEmpty()) continue
            parseExamRow(cells, headerIndex, offset + 1)?.let { parsed.add(it) }
        }

        if (rows.size > 1 && parsed.isEmpty()) {
            throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "考试安排")
        }
        return parsed
    }

    private enum class ExamColumn { ID, COURSE_ID, NAME, DATE, TIME, COMBINED_TIME, LOCATION }

    private fun examHeaderIndex(headers: List<String>): Map<ExamColumn, Int> {
        val result = mutableMapOf<ExamColumn, Int>()
        for ((index, header) in headers.withIndex()) {
            val compact = header.replace(" ", "")
            when {
                compact.contains("序号") -> result[ExamColumn.ID] = index
                compact.contains("课程编号") || compact.contains("课程代码") || compact == "课号" ->
                    result[ExamColumn.COURSE_ID] = index
                compact.contains("课程名称") || compact == "课程" || compact == "科目" ->
                    result[ExamColumn.NAME] = index
                compact.contains("考试时间") || compact.contains("时间地点") ->
                    result[ExamColumn.COMBINED_TIME] = index
                compact.contains("考试日期") || compact == "日期" -> result[ExamColumn.DATE] = index
                compact == "时间" || compact.contains("考试时段") -> result[ExamColumn.TIME] = index
                compact.contains("考试地点") || compact.contains("地点") || compact.contains("教室") ->
                    result[ExamColumn.LOCATION] = index
            }
        }
        return result
    }

    private fun parseExamRow(
        cells: List<String>,
        headerIndex: Map<ExamColumn, Int>,
        fallbackId: Int,
    ): ParsedExamRecord? {
        val id = value(ExamColumn.ID, cells, headerIndex)
            ?.let { it.replace(Regex("[^0-9]"), "").toIntOrNull() }
            ?: cells.getOrNull(0)?.replace(Regex("[^0-9]"), "")?.toIntOrNull()
            ?: fallbackId

        val name = firstNonEmpty(
            value(ExamColumn.NAME, cells, headerIndex),
            cells.getOrNull(3),
            cells.getOrNull(2),
        ) ?: return null

        val courseId = firstNonEmpty(
            value(ExamColumn.COURSE_ID, cells, headerIndex),
            cells.getOrNull(2),
            cells.getOrNull(1),
        ) ?: ""

        val location = firstNonEmpty(
            value(ExamColumn.LOCATION, cells, headerIndex),
            cells.getOrNull(5),
            cells.lastOrNull(),
        ) ?: ""

        val time = parseExamTime(
            dateText = value(ExamColumn.DATE, cells, headerIndex),
            timeText = value(ExamColumn.TIME, cells, headerIndex),
            combinedText = firstNonEmpty(
                value(ExamColumn.COMBINED_TIME, cells, headerIndex),
                cells.getOrNull(4),
                cells.firstOrNull { it.contains(":") || it.contains("：") },
            ),
        ) ?: return null

        return ParsedExamRecord(
            id = id,
            courseId = courseId,
            name = name,
            date = time.date,
            start = time.start,
            end = time.end,
            location = location,
        )
    }

    private fun value(column: ExamColumn, cells: List<String>, headerIndex: Map<ExamColumn, Int>): String? {
        val index = headerIndex[column] ?: return null
        return cells.getOrNull(index)?.takeIf { it.isNotEmpty() }
    }

    private fun firstNonEmpty(vararg values: String?): String? =
        values.firstNotNullOfOrNull { it?.trim()?.takeIf(String::isNotEmpty) }

    private fun parseExamTime(
        dateText: String?,
        timeText: String?,
        combinedText: String?,
    ): ExamTime? {
        val combined = listOf(dateText, timeText, combinedText)
            .filterNotNull()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .joinToString(" ")
            .let(::normalizedExamText)

        val date = extractExamDate(combined) ?: return null
        val timeRange = extractExamTimeRange(combined) ?: return null
        return ExamTime(date, timeRange.first, timeRange.second)
    }

    private fun extractExamDate(text: String): String? {
        Regex(FULL_DATE_PATTERN).find(text)?.let { match ->
            val year = match.groupValues[1].toIntOrNull() ?: return@let
            val month = match.groupValues[2].toIntOrNull() ?: return@let
            val day = match.groupValues[3].toIntOrNull() ?: return@let
            return "%04d-%02d-%02d".format(year, month, day)
        }
        Regex(SHORT_DATE_PATTERN).find(text)?.let { match ->
            val month = match.groupValues[1].toIntOrNull() ?: return@let
            val day = match.groupValues[2].toIntOrNull() ?: return@let
            return "%04d-%02d-%02d".format(LocalDate.now().year, month, day)
        }
        return null
    }

    private fun extractExamTimeRange(text: String): Pair<String, String>? {
        val match = Regex(TIME_RANGE_PATTERN).find(text) ?: return null
        val startHour = match.groupValues[1].toIntOrNull() ?: return null
        val endHour = match.groupValues[3].toIntOrNull() ?: return null
        val start = "%02d:%s".format(startHour, match.groupValues[2])
        val end = "%02d:%s".format(endHour, match.groupValues[4])
        return start to end
    }

    // MARK: - 空教室

    override fun parseEmptyClassrooms(html: String): List<EmptyClassroom> {
        val document = Jsoup.parse(html)
        val rows = document.select("#dataList tr")
        if (rows.size <= 4) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "空教室")

        val dataRows = rows.subList(2, rows.size - 2)
        val result = mutableListOf<Pair<Int, EmptyClassroom>>()
        for (row in dataRows) {
            val texts = row.select("td").map { normalizedClassroomCellText(it.text()) }
            if (texts.size <= 1) continue
            if (texts.drop(1).any { it.isNotEmpty() }) continue
            parseClassroomRow(texts[0])?.let { result.add(it) }
        }
        return result
            .sortedWith(compareByDescending<Pair<Int, EmptyClassroom>> { it.first }.thenBy { it.second.room })
            .map { it.second }
    }

    private fun parseClassroomRow(text: String): Pair<Int, EmptyClassroom>? {
        val normalized = normalizedClassroomCellText(text)
            .replace("（", "(")
            .replace("）", ")")
        val match = Regex(CLASSROOM_ROW_PATTERN).find(normalized) ?: return null
        val rawBuilding = match.groupValues[1]
            .trim()
            .replace(" ", "")
            .replace("　", "")
        val room = match.groupValues[2].uppercase()
        val mapped = classroomBuildingMap[rawBuilding] ?: return null
        return mapped.first to EmptyClassroom(building = mapped.second, room = room)
    }

    private fun normalizedClassroomCellText(text: String): String =
        text.trim()
            .replace("\u00A0", "")
            .replace(" ", "")
            .replace("　", "")

    // MARK: - 辅助

    private fun normalizedTableCellText(element: Element): String =
        element.text()
            .trim()
            .replace("\u00A0", " ")
            .replace(Regex("\\s+"), " ")

    private fun normalizedExamText(text: String): String =
        text.trim()
            .replace(Regex("\\s+"), " ")
            .replace("－", "-")
            .replace("—", "-")
            .replace("–", "-")
            .replace("～", "~")

    private fun candidateDataTables(document: org.jsoup.nodes.Document): List<Element> {
        val tables = mutableListOf<Element>()
        for (selector in listOf("#dataList", "table.Nsb_r_list", "table")) {
            for (table in document.select(selector)) {
                val html = table.outerHtml()
                if (tables.none { it.outerHtml() == html }) {
                    tables.add(table)
                }
            }
        }
        return tables
    }

    private fun parseCredit(text: String): Double? {
        val normalized = text.replace("学分", "").replace("：", ":").trim()
        normalized.toDoubleOrNull()?.let { return it }
        return Regex(CREDIT_PATTERN).find(normalized)?.value?.toDoubleOrNull()
    }

    private fun String.firstInteger(): Int? = Regex("\\d+").find(this)?.value?.toIntOrNull()

    private fun parseOfficialDecimal(text: String, labels: List<String>, maxValue: Double?): Double? {
        for (label in labels) {
            val escaped = Regex.escape(label)
            val patterns = listOf(
                Regex("$escaped\\s*(?:为|是|:|：)?\\s*([0-9]+(?:\\.[0-9]+)?)"),
                Regex("$escaped[^0-9]{0,12}([0-9]+(?:\\.[0-9]+)?)"),
            )
            for (pattern in patterns) {
                val value = pattern.find(text)?.groupValues?.getOrNull(1)?.toDoubleOrNull() ?: continue
                if (value >= 0 && (maxValue == null || value <= maxValue)) return value
            }
        }
        return null
    }

    private data class CourseData(
        val courseName: String,
        val teacher: String,
        val classInfo: String,
        val room: String,
        val location: String,
        val duration: List<Int>,
    )

    private data class ExamTime(val date: String, val start: String, val end: String)

    private companion object {
        const val totalWeeks = 20
        const val totalDays = 7

        val durationSlots = listOf(
            listOf(1, 2), listOf(3, 4), listOf(5), listOf(6, 7), listOf(8, 9), listOf(10, 11), listOf(12),
        )

        val locationMap = mapOf(
            "教" to "一教",
            "计算中心-" to "学研A座",
            "A" to "学研A座",
            "A座" to "学研A座",
            "学研A座" to "学研A座",
            "B" to "学研B座",
            "B座" to "学研B座",
            "学研B座" to "学研B座",
            "C" to "学研C座",
            "C座" to "学研C座",
            "学研C座" to "学研C座",
            "第一教学楼" to "一教",
            "一教学楼" to "一教",
            "一教" to "一教",
            "一教楼" to "一教",
            "第二教学楼" to "二教",
            "二教学楼" to "二教",
            "二教" to "二教",
            "二教楼" to "二教",
            "第三教学楼" to "三教",
            "三教学楼" to "三教",
            "三教" to "三教",
            "三教楼" to "三教",
            "基础楼" to "基础楼",
            "林业楼" to "林业楼",
            "生物楼" to "生物楼",
            "实验楼" to "实验楼",
        )

        const val WEEK_TOKEN = "\\d+(?:-\\d+)?"
        const val DURATION_PATTERN = "第?(\\d+)(?:-(\\d+))?节"
        const val CREDIT_PATTERN = "\\d+(?:\\.\\d+)?"
        const val FULL_DATE_PATTERN = "(\\d{4})[-/.年](\\d{1,2})[-/.月](\\d{1,2})"
        const val SHORT_DATE_PATTERN = "(\\d{1,2})[月/-](\\d{1,2})日?"
        const val TIME_RANGE_PATTERN = "(\\d{1,2})[:：](\\d{2})\\s*(?:~|～|—|–|-|至|到)\\s*(\\d{1,2})[:：](\\d{2})"
        const val CLASSROOM_ROW_PATTERN = "^([^\\(\\d]+?)(\\d+[A-Za-z]?)(?:\\((\\d+)\\s*/\\s*(\\d+)\\))?$"

        val explicitEmptyTimetableMarkers = listOf(
            "课表暂未公布",
            "暂无课表",
            "没有找到符合条件的课表",
        )

        val classroomBuildingMap = mapOf(
            "A" to (10 to "学研A座"),
            "A座" to (10 to "学研A座"),
            "学研A" to (10 to "学研A座"),
            "学研A座" to (10 to "学研A座"),
            "学研楼A座" to (10 to "学研A座"),
            "B" to (9 to "学研B座"),
            "B座" to (9 to "学研B座"),
            "学研B" to (9 to "学研B座"),
            "学研B座" to (9 to "学研B座"),
            "学研楼B座" to (9 to "学研B座"),
            "C" to (8 to "学研C座"),
            "C座" to (8 to "学研C座"),
            "学研C" to (8 to "学研C座"),
            "学研C座" to (8 to "学研C座"),
            "学研楼C座" to (8 to "学研C座"),
            "第一教学楼" to (8 to "一教"),
            "一教学楼" to (8 to "一教"),
            "一教" to (8 to "一教"),
            "一教楼" to (8 to "一教"),
            "第二教学楼" to (7 to "二教"),
            "二教学楼" to (7 to "二教"),
            "二教" to (7 to "二教"),
            "二教楼" to (7 to "二教"),
            "第三教学楼" to (6 to "三教"),
            "三教学楼" to (6 to "三教"),
            "三教" to (6 to "三教"),
            "三教楼" to (6 to "三教"),
            "基础楼" to (5 to "基础楼"),
            "林业楼" to (4 to "林业楼"),
            "生物楼" to (3 to "生物楼"),
            "实验楼" to (2 to "实验楼"),
        )
    }
}
