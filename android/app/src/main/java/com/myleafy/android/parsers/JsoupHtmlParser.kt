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
        val tables = candidateDataTables(document)
        for (table in tables) {
            val rows = table.select("tr")
            val headerIndex = rows.indexOfFirst { row ->
                val labels = row.select("th,td").map { it.text().trim() }
                labels.containsAll(listOf("课程名称", "成绩", "学分"))
            }
            if (headerIndex < 0) continue
            val headings = rows[headerIndex].select("th,td").map { it.text().trim() }
            val parsed = mutableListOf<ParsedGradeRecord>()
            for (row in rows.drop(headerIndex + 1)) {
                val cells = row.select("td").map { it.text().trim() }
                if (cells.isEmpty() || cells.all { it.isEmpty() } || cells.joinToString("").let { it.contains("暂无数据") || it.contains("无记录") }) continue
                fun value(vararg names: String): String = cells.getOrNull(headings.indexOfFirst { it in names }).orEmpty()
                val term = value("开课学期", "学期")
                val name = value("课程名称")
                val credit = value("学分")
                if (term.isEmpty() || name.isEmpty() || parseCredit(credit) == null) {
                    throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "成绩")
                }
                val attribute = value("课程属性")
                val category = value("课程分类", "课程性质", "课程类别")
                parsed += ParsedGradeRecord(term, name, credit, value("成绩"),
                    listOf(attribute, category).filter(String::isNotEmpty).joinToString(" · "),
                    value("课程编号", "课程代码").ifBlank { null }, attribute, category, value("考试性质"))
            }
            return parsed
        }
        throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "成绩")
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
        val document = Jsoup.parse(html)
        val visible = document.clone()
        visible.select("table,script,style,template,[hidden],[aria-hidden=true]").remove()
        val pageText = visible.text().replace(Regex("\\s+"), " ").trim()
        fun official(labels: List<String>, max: Double?): Double? {
            document.select("tr").forEach { row ->
                val cells = row.select("th,td").map { it.text().replace("（", "(").replace("）", ")").trim() }
                cells.forEachIndexed { index, text ->
                    if (labels.any { text.equals(it, ignoreCase = true) }) {
                        cells.getOrNull(index + 1)?.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 && (max == null || it <= max) }?.let { return it }
                    }
                }
            }
            return parseOfficialDecimal(pageText, labels, max)
        }
        val summary = ParsedGradeSummary(
            officialGpa = official(
                labels = listOf("平均学分绩点(GPA)", "平均绩点(GPA)", "平均学分绩点", "平均绩点", "学分绩点", "GPA"),
                max = 5.0,
            ),
            officialWeightedAverage = official(
                labels = listOf("加权平均分", "加权均分"),
                max = 100.0,
            ),
            officialCreditPoint = official(labels = listOf("学分积"), max = null),
        )
        for (table in Jsoup.parse(html).select("table")) {
            val rows = expandedTableRows(table)
            val header = rows.indexOfFirst { row -> row.any { it.replace(" ", "") == "所得学分" } && row.any { it.replace(" ", "") == "必修学分" } }
            if (header < 0) continue
            val top = rows[header].map { it.replace(" ", "") }
            val totalColumn = top.indexOf("所得学分")
            val dataIndex = (header + 1 until rows.size).firstOrNull { rows[it].getOrNull(totalColumn)?.toDoubleOrNull() != null }
                ?: throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "所得学分详情")
            val cells = rows[dataIndex]
            if (cells.size != top.size) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "所得学分详情")
            val bottom = rows[dataIndex - 1]
            val raw = linkedMapOf<String, String>()
            val buckets = linkedMapOf<String, Double>()
            var required: Double? = null
            var professional: Double? = null
            var major: Double? = null
            var cross: Double? = null
            var publicTotal: Double? = null
            top.forEachIndexed { index, group ->
                if (group == "序号") return@forEachIndexed
                val text = cells[index].trim()
                val value = if (text.isEmpty()) 0.0 else text.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 }
                if (value == null) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "所得学分详情：$group")
                val leaf = bottom.getOrNull(index).orEmpty().replace(" ", "")
                raw[if (group == leaf) group else "$group/$leaf"] = text
                if (group == "必修学分") required = value
                if (group.contains("专业选修")) {
                    if (leaf in listOf("总计", "合计") || leaf == group) professional = value
                    if (leaf == "本专业") { major = value; raw["本专业选修"] = text }
                    if (leaf == "外专业") cross = value
                }
                if (group.contains("公共选修") || group.contains("通识选修")) {
                    if (leaf in listOf("总计", "合计") || leaf == group) { publicTotal = value; raw["公共选修总计"] = text }
                    else buckets[bottom.getOrNull(index).orEmpty()] = value
                }
            }
            raw["所得学分"] = cells[totalColumn]
            return summary.copy(totalCredits = cells[totalColumn].toDouble(), requiredCredits = required,
                professionalElectiveCredits = professional, professionalMajorElectiveCredits = major,
                professionalCrossMajorElectiveCredits = cross, publicElectiveCredits = publicTotal,
                publicElectiveBuckets = buckets, rawFields = raw)
        }
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

    override fun parseClassroomAvailability(html: String): ClassroomAvailability {
        val table = Jsoup.parse(html).selectFirst("#dataList")
            ?: throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "教室占用矩阵")
        if (!table.select("th").text().contains("星期")) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "教室占用矩阵")
        val columns = table.select("td[tdvalue]").map { cell ->
            val value = cell.attr("tdvalue").trim()
            if (value.isEmpty() || value.length % 2 != 0 || !value.all(Char::isDigit)) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "教室节次")
            value.chunked(2).map { part -> part.toInt().also { if (it !in 1..12) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "教室节次") } }
        }
        val periods = columns.flatten()
        if (periods.isEmpty() || periods.distinct().size != periods.size) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "教室节次")
        val rows = table.select("tr[jsbh]").mapNotNull { row ->
            val cells = row.select("td")
            if (cells.size != columns.size + 1) throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "教室占用行")
            val room = parseClassroomRow(cells[0].text()) ?: return@mapNotNull null
            val slots = columns.flatMapIndexed { index, column ->
                val symbols = java.text.Normalizer.normalize(cells[index + 1].text(), java.text.Normalizer.Form.NFKC).filterNot(Char::isWhitespace)
                val status = when { symbols.isEmpty() -> ClassroomStatus.AVAILABLE; symbols.all { it in "◆LGKΚXJ" } -> ClassroomStatus.OCCUPIED; else -> ClassroomStatus.UNKNOWN }
                column.map { ClassroomSlot(it, status) }
            }
            room.first to ClassroomAvailabilityRow(room.second, slots.sortedBy { it.period })
        }
        if (table.select("tr[jsbh]").isEmpty() && table.select("tr").any { row -> row.select("td").size > 1 && row.select("td[tdvalue]").isEmpty() && listOf("暂无", "无数据", "符号说明").none { row.text().contains(it) } })
            throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "教室占用矩阵")
        return ClassroomAvailability(periods, rows.sortedWith(compareByDescending<Pair<Int, ClassroomAvailabilityRow>> { it.first }.thenBy { it.second.room.room }).map { it.second })
    }

    override fun parseEmptyClassrooms(html: String): List<EmptyClassroom> =
        parseClassroomAvailability(html).available(1, 12)

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

    // MARK: - 教学计划 / 培养方案

    override fun parseTeachingPlan(html: String): List<ParsedTeachingPlanSection> {
        val document = Jsoup.parse(html)
        for (table in candidateDataTables(document)) {
            val rows = expandedTableRows(table)
            if (rows.isEmpty()) continue
            val headers = rows[0]
            val termIndex = headers.indexOfFirst { it.contains("开课学期") || it == "学期" }
            val nameIndex = headers.indexOfFirst { it.contains("课程名称") }
            val creditIndex = headers.indexOfFirst { it.contains("学分") }
            if (termIndex < 0 || nameIndex < 0 || creditIndex < 0) continue

            fun columnIndex(vararg keys: String): Int =
                headers.indexOfFirst { header -> keys.any { header.contains(it) } }

            val unitIndex = columnIndex("开课单位")
            val durationIndex = columnIndex("总学时", "学时")
            val typeIndex = columnIndex("课程属性")
            val categoryIndex = columnIndex("课程分类", "课程性质")
            val examIndex = columnIndex("考试性质", "考核方式")
            val codeIndex = columnIndex("课程编号", "课程代码")

            val sections = LinkedHashMap<String, MutableList<ParsedTeachingPlanCourse>>()
            var currentTerm = ""
            var parsedAny = false
            for (row in rows.drop(1)) {
                val cells = row
                if (cells.isEmpty()) continue
                val rowText = cells.joinToString("")
                if (rowText.contains("暂无数据") || rowText.contains("无记录")) continue
                if (cells.all { it.isBlank() }) continue

                val termCell = cells.getOrNull(termIndex)?.trim().orEmpty()
                if (termCell.isNotEmpty()) currentTerm = termCell

                val name = cells.getOrNull(nameIndex)?.trim().orEmpty()
                val creditValue = cells.getOrNull(creditIndex)?.let { parseCredit(it) }
                if (name.isEmpty() || currentTerm.isEmpty() || creditValue == null) {
                    throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_ROWS_UNPARSEABLE, "教学计划")
                }
                parsedAny = true
                sections.getOrPut(currentTerm) { mutableListOf() }.add(
                    ParsedTeachingPlanCourse(
                        courseCode = cells.getOrNull(codeIndex)?.trim().orEmpty(),
                        name = name,
                        unit = cells.getOrNull(unitIndex)?.trim().orEmpty(),
                        credit = cells.getOrNull(creditIndex)?.trim().orEmpty(),
                        duration = cells.getOrNull(durationIndex)?.trim().orEmpty(),
                        type = cells.getOrNull(typeIndex)?.trim().orEmpty(),
                        courseCategory = cells.getOrNull(categoryIndex)?.trim().orEmpty(),
                        exam = cells.getOrNull(examIndex)?.trim().orEmpty(),
                    ),
                )
            }
            if (!parsedAny) return emptyList()
            return sections.map { (term, courses) -> ParsedTeachingPlanSection(term, courses) }
        }
        throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "教学计划")
    }

    override fun parseTrainingProgram(html: String): ParsedTrainingProgram {
        val document = Jsoup.parse(html)
        val tables = candidateDataTables(document)
        val title = resolveTrainingProgramTitle(document)
        val sections = parseTrainingProgramSections(document)
        val creditRequirements = parseTrainingCreditRequirements(tables)
        if (sections.isEmpty() && creditRequirements.isEmpty()) {
            throw HtmlParseError(HtmlParseError.ParseErrorKind.TABLE_NOT_FOUND, "培养方案明细")
        }
        val rawTables = tables
            .filter { it.select("table").size == 1 }
            .map { table ->
                ParsedTrainingProgramTable(
                    expandedTableRows(table).filter { it.any(String::isNotBlank) },
                )
            }
            .filter { it.rows.isNotEmpty() }
        return ParsedTrainingProgram(
            title = title,
            sections = sections,
            tables = rawTables,
            creditRequirements = creditRequirements,
        )
    }

    private fun resolveTrainingProgramTitle(document: org.jsoup.nodes.Document): String {
        document.select("p").firstOrNull { it.text().contains("专业本科培养方案") }?.let {
            return it.text().trim()
        }
        Regex("([^，。；\\s]{2,40}专业本科培养方案)").find(document.text())?.let {
            return it.groupValues[1]
        }
        return "专业培养方案"
    }

    private fun parseTrainingProgramSections(document: org.jsoup.nodes.Document): List<ParsedTrainingProgramSection> {
        val result = mutableListOf<ParsedTrainingProgramSection>()
        var currentTitle: String? = null
        var currentBody = StringBuilder()
        var currentLinks = mutableListOf<ParsedTrainingProgramLink>()

        fun flush() {
            val title = currentTitle ?: return
            result.add(
                ParsedTrainingProgramSection(
                    title = title,
                    body = currentBody.toString().trim(),
                    links = currentLinks.toList(),
                ),
            )
            currentBody = StringBuilder()
            currentLinks = mutableListOf()
        }

        for (paragraph in document.select("p")) {
            if (paragraph.parents().any { it.tagName() == "table" }) continue
            val text = normalizedTableCellText(paragraph)
            if (trainingSectionHeading.matches(text)) {
                flush()
                currentTitle = text
                continue
            }
            if (currentTitle == null) continue
            val links = paragraph.select("a[href]").mapNotNull { anchor ->
                val url = anchor.absUrl("href").ifBlank { anchor.attr("href") }
                if (!url.startsWith("http://") && !url.startsWith("https://")) return@mapNotNull null
                ParsedTrainingProgramLink(anchor.text().trim().ifBlank { url }, url)
            }
            currentLinks.addAll(links)
            val bodyText = text.removePrefix(currentTitle.orEmpty()).trim()
            if (bodyText.isNotEmpty()) {
                if (currentBody.isNotEmpty()) currentBody.append('\n')
                currentBody.append(bodyText)
            }
        }
        flush()
        return result
    }

    /** Resolve merged cells before reading a column; never treat the first number as credits. */
    private fun expandedTableRows(table: Element): List<List<String>> {
        val spans = mutableMapOf<Int, Pair<String, Int>>()
        return table.select("tr").filter { it.parents().firstOrNull { p -> p.tagName() == "table" } === table }.map { row ->
            val values = mutableMapOf<Int, String>()
            spans.toMap().forEach { (column, span) ->
                values[column] = span.first
                if (span.second <= 1) spans.remove(column) else spans[column] = span.first to span.second - 1
            }
            var column = 0
            row.children().filter { it.tagName() in listOf("td", "th") }.forEach { cell ->
                while (column in values) column++
                val text = normalizedTableCellText(cell)
                val width = (cell.attr("colspan").toIntOrNull() ?: 1).coerceIn(1, 100)
                val height = (cell.attr("rowspan").toIntOrNull() ?: 1).coerceIn(1, 1000)
                repeat(width) {
                    values[column] = text
                    if (height > 1) spans[column] = text to height - 1
                    column++
                }
            }
            (0..(values.keys.maxOrNull() ?: -1)).map { values[it].orEmpty() }
        }
    }

    private fun parseTrainingCreditRequirements(tables: List<Element>): List<ParsedGraduationCreditRequirement> {
        val requirements = mutableListOf<ParsedGraduationCreditRequirement>()
        for (table in tables) {
            val rows = expandedTableRows(table)
            val richHeader = rows.indexOfFirst { row -> row.any { it.contains("应修学分") || it.contains("学分要求") || it.contains("要求学分") } }
            if (richHeader >= 0) {
                val headers = rows[richHeader]
                val requiredIndex = headers.indexOfFirst { it.contains("应修学分") || it.contains("学分要求") || it.contains("要求学分") }
                val plannedIndex = headers.indexOfFirst { it.contains("计划学分") }
                val categoryIndex = headers.indexOfFirst { it.contains("类别") || it.contains("性质") || it.contains("分类") }
                val nameIndex = headers.indexOfFirst { it.contains("课程名称") || it == "名称" }
                rows.drop(richHeader + 1).forEach { cells ->
                    val required = cells.getOrNull(requiredIndex)?.removeSuffix("学分")?.trim()?.toDoubleOrNull()?.takeIf { it in 0.0..500.0 } ?: return@forEach
                    val courseName = cells.getOrNull(nameIndex).orEmpty()
                    val label = cells.getOrNull(categoryIndex)?.takeIf(String::isNotBlank) ?: courseName
                    if (label.isBlank()) return@forEach
                    val aggregate = nameIndex < 0 || listOf("总计", "合计", "小计", "毕业", "应修", "要求").any { courseName.contains(it) || label.contains(it) }
                    val total = label.contains("总学分") || courseName.contains("总学分") || label.trim() in listOf("合计", "总计")
                    requirements += ParsedGraduationCreditRequirement(if (total) "毕业生应取得总学分" else cleanTrainingCreditLabel(label), required,
                        total, courseName,
                        cells.getOrNull(plannedIndex)?.toDoubleOrNull()?.takeIf { it in 0.0..500.0 }, aggregate)
                }
                if (nameIndex < 0) continue
            }
            val totalLabel: (String) -> Boolean = { it.replace(" ", "").let { label -> label.contains("应取得总学分") || label.contains("毕业总学分") } }
            val footerStart = rows.indexOfFirst { row -> row.any(totalLabel) }
            if (footerStart < 0) continue
            // The school's course catalogue has a merged-cell requirements footer. Its columns
            // differ from the catalogue header: only read adjacent label/value runs below the total.
            if (rows.take(4).any { row -> row.any { it.contains("课程编号") || it.contains("课程名称") || it.contains("课程代码") } }) {
                for (row in rows.drop(footerStart)) {
                    val runs = row.filter(String::isNotBlank).fold(mutableListOf<String>()) { result, cell ->
                        if (result.lastOrNull() != cell) result += cell
                        result
                    }
                    for (index in 0 until runs.lastIndex) {
                        val label = runs[index].replace(" ", "")
                        if (!totalLabel(label) && !(label.endsWith("学分") && trainingCreditLabels.any { label.contains(it) })) continue
                        val raw = runs[index + 1].trim()
                        if (!raw.matches(Regex("[0-9]+(?:\\.[0-9]+)?"))) continue
                        val credits = raw.toDoubleOrNull()?.takeIf { it in 0.0..500.0 } ?: continue
                        requirements += ParsedGraduationCreditRequirement(if (totalLabel(label)) "毕业生应取得总学分" else cleanTrainingCreditLabel(label), credits, totalLabel(label))
                    }
                }
                continue
            }
            val header = rows.firstOrNull { row -> row.any { it == "学分" || it.contains("学分要求") || it.contains("最低学分") } }
            val creditColumn = header?.indexOfFirst { it == "学分" || it.contains("学分要求") || it.contains("最低学分") } ?: -1
            for (row in rows) {
                val labelIndex = row.indexOfFirst { text -> totalLabel(text) || trainingCreditLabels.any { text.contains(it) } }
                if (labelIndex < 0) continue
                val label = row[labelIndex]
                if (label.length >= 45 || label.contains("学时") || label.contains("占比")) continue
                val distinct = row.distinct().filter(String::isNotBlank)
                val value = if (creditColumn >= 0 && creditColumn != labelIndex) row.getOrNull(creditColumn)
                    else if (distinct.size == 2 && distinct.first() == label) distinct.last() else null
                // Credits are a whole cell, never a number extracted from a code or a prose sentence.
                val raw = value?.removeSuffix("学分")?.trim() ?: continue
                if (!raw.matches(Regex("[0-9]+(?:\\.[0-9]+)?"))) continue
                val credits = raw.toDoubleOrNull()?.takeIf { it in 0.0..500.0 } ?: continue
                requirements += ParsedGraduationCreditRequirement(
                    label = if (totalLabel(label)) "毕业生应取得总学分" else cleanTrainingCreditLabel(label),
                    credits = credits, isTotal = totalLabel(label),
                )
            }
        }
        return requirements.distinctBy { "${it.label}|${it.courseName}|${it.isAggregate}" }
    }

    private fun cleanTrainingCreditLabel(label: String): String =
        label.replace("最低选修学分", "").replace("最低选修", "").replace("学分", "").trim()

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

        val trainingSectionHeading = Regex("^[一二三四五六七八九十]+[、.．].{2,40}$")

        val trainingCreditLabels = listOf(
            "通识选修课",
            "通识必修课",
            "专业基础课",
            "专业核心课",
            "本专业选修课最低选修学分",
            "集中性实践环节",
            "毕业论文（设计）",
            "拓展教育",
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
