import Foundation
import SwiftSoup

nonisolated enum HTMLParserError: LocalizedError {
    case timetableTableNotFound
    case noTimetableCourses
    case tableNotFound(String)
    case tableRowsUnparseable(String)
    
    var errorDescription: String? {
        switch self {
        case .timetableTableNotFound:
            return "未找到课表表格，页面结构可能已变更"
        case .noTimetableCourses:
            return "页面已返回，但未解析到任何课程"
        case .tableNotFound(let name):
            return "未找到\(name)数据表格，页面结构可能已变更"
        case .tableRowsUnparseable(let name):
            return "\(name)数据表格已返回，但没有解析到有效记录，页面列或时间格式可能已变更"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private nonisolated extension String {
    func matches(for pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard let range = Range(match.range, in: self) else { return nil }
            return String(self[range])
        }
    }

    var normalizedExamText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "～", with: "~")
    }

    var normalizedDigitsOnly: String {
        replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
    }
}

nonisolated struct CourseData {
    var courseName: String
    var teacher: String
    var classInfo: String
    var room: String
    var location: String
    var duration: [Int]
}

nonisolated struct ParsedCourseRecord: Sendable {
    var courseName: String
    var teacher: String
    var classInfo: String
    var room: String
    var location: String
    var dayOfWeek: Int
    var weeks: [Int]
    var duration: [Int]

    @MainActor
    func makeCourse() -> Course {
        Course(
            courseName: courseName,
            teacher: teacher,
            classInfo: classInfo,
            room: room,
            location: location,
            dayOfWeek: dayOfWeek,
            weeks: weeks,
            duration: duration
        )
    }
}

nonisolated private struct GraduateSchedulePayload: Decodable {
    let rows: [GraduateScheduleRow]
}

nonisolated private struct GraduateScheduleRow: Decodable {
    let mc: String?
    let columns: [String: String]

    nonisolated struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var values: [String: String] = [:]
        var title: String?

        for key in container.allKeys {
            let value = (try? container.decode(String.self, forKey: key)) ?? ""
            if key.stringValue == "mc" {
                title = value
            }
            values[key.stringValue] = value
        }

        self.mc = title
        self.columns = values
    }
}

class HTMLParser {
    
    nonisolated private static let durationSlots: [[Int]] = [
        [1, 2], [3, 4], [5], [6, 7], [8, 9], [10, 11], [12]
    ]
    nonisolated private static let totalWeeks = 20
    nonisolated private static let totalDays = 7

    nonisolated private static let locationMap: [String: String] = [
        "教": "一教",
        "计算中心-": "学研A座",
        "A": "学研A座",
        "A座": "学研A座",
        "学研A座": "学研A座",
        "B": "学研B座",
        "B座": "学研B座",
        "学研B座": "学研B座",
        "C": "学研C座",
        "C座": "学研C座",
        "学研C座": "学研C座",
        "第一教学楼": "一教",
        "一教学楼": "一教",
        "一教": "一教",
        "一教楼": "一教",
        "第二教学楼": "二教",
        "二教学楼": "二教",
        "二教": "二教",
        "二教楼": "二教",
        "第三教学楼": "三教",
        "三教学楼": "三教",
        "三教": "三教",
        "三教楼": "三教",
        "基础楼": "基础楼",
        "林业楼": "林业楼",
        "生物楼": "生物楼",
        "实验楼": "实验楼"
    ]

    nonisolated private static func parseClassroomBuilding(loc: String) -> (room: String, location: String) {
        let normalized = loc
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        guard let firstDigitIndex = normalized.firstIndex(where: { character in
            guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
                return false
            }
            return scalar.value >= 48 && scalar.value <= 57
        }) else {
            return (normalized, normalized)
        }

        let prefix = String(normalized[..<firstDigitIndex])
        let room = String(normalized[firstDigitIndex...])
        let location = locationMap[prefix] ?? prefix
        return (room, location)
    }

    nonisolated private static func parseWeeks(weeksString: String) -> [Int] {
        let compact = weeksString.replacingOccurrences(of: " ", with: "")
        let oddOnly = compact.contains("单")
        let evenOnly = compact.contains("双")

        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:-\d+)?"#) else {
            return []
        }

        let range = NSRange(compact.startIndex..., in: compact)
        let matches = regex.matches(in: compact, range: range)
        var weeks: Set<Int> = []

        for match in matches {
            guard let tokenRange = Range(match.range, in: compact) else { continue }
            let token = String(compact[tokenRange])

            if token.contains("-") {
                let bounds = token.components(separatedBy: "-")
                if bounds.count == 2, let start = Int(bounds[0]), let end = Int(bounds[1]), start <= end {
                    weeks.formUnion(start...end)
                }
            } else if let week = Int(token) {
                weeks.insert(week)
            }
        }

        let filtered = weeks.filter { week in
            if oddOnly { return week % 2 == 1 }
            if evenOnly { return week % 2 == 0 }
            return true
        }

        return filtered.sorted()
    }

    nonisolated private static func parseGraduateWeeks(_ weeksString: String) -> [Int] {
        let compact = weeksString.replacingOccurrences(of: " ", with: "")
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:-\d+)?"#) else {
            return []
        }

        let range = NSRange(compact.startIndex..., in: compact)
        let matches = regex.matches(in: compact, range: range)
        var weeks: Set<Int> = []

        for match in matches {
            guard let tokenRange = Range(match.range, in: compact) else { continue }
            let token = String(compact[tokenRange])

            if token.contains("-") {
                let bounds = token.components(separatedBy: "-")
                if bounds.count == 2,
                   let start = Int(bounds[0]),
                   let end = Int(bounds[1]),
                   start <= end {
                    weeks.formUnion(start...end)
                }
            } else if let week = Int(token) {
                weeks.insert(week)
            }
        }

        return weeks.sorted()
    }

    nonisolated private static func parseDuration(from text: String) -> [Int] {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard let regex = try? NSRegularExpression(pattern: #"第?(\d+)(?:-(\d+))?节"#) else {
            return []
        }

        let range = NSRange(compact.startIndex..., in: compact)
        guard let match = regex.firstMatch(in: compact, range: range),
              let startRange = Range(match.range(at: 1), in: compact),
              let start = Int(compact[startRange]) else {
            return []
        }

        if let endRange = Range(match.range(at: 2), in: compact),
           let end = Int(compact[endRange]),
           start <= end {
            return Array(start...end)
        }

        return [start]
    }

    nonisolated private static func parseDayAndDuration(from element: Element) throws -> (dayOfWeek: Int, duration: [Int])? {
        let id = try element.attr("id").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        let parts = id.components(separatedBy: "_")
        guard parts.count >= 3,
              parts[0] == "kbcontent",
              let dayOfWeek = Int(parts[1]),
              let periodIndex = Int(parts[2]),
              (1...totalDays).contains(dayOfWeek) else {
            return nil
        }

        let text = try element.text()
        let explicitDuration = parseDuration(from: text)
        if !explicitDuration.isEmpty {
            return (dayOfWeek, explicitDuration)
        }

        if durationSlots.indices.contains(periodIndex - 1) {
            return (dayOfWeek, durationSlots[periodIndex - 1])
        }

        return (dayOfWeek, [periodIndex])
    }

    nonisolated private static func parseStudentClassBlock(_ items: [String], duration: [Int]) -> (CourseData, [Int]) {
        var name = ""
        var teacher = ""
        var weeksString = ""
        var room = ""
        var location = ""

        for (index, item) in items.enumerated() {
            guard let firstChar = item.first else { continue }

            if index == 0 {
                name = item
            } else if index == 1 && !firstChar.isNumber {
                teacher = item
            } else if item.contains("节") && firstChar.isNumber {
                if weeksString.isEmpty || item.contains("周") {
                    weeksString = item
                }
            } else if firstChar.isNumber || item.contains("周") {
                if weeksString.isEmpty || (!weeksString.contains("周") && item.contains("周")) {
                    weeksString = item
                } else {
                    let parsed = parseClassroomBuilding(loc: item)
                    if room.isEmpty {
                        room = parsed.room
                        location = parsed.location
                    }
                }
            } else {
                let parsed = parseClassroomBuilding(loc: item)
                room = parsed.room
                location = parsed.location
            }
        }

        let data = CourseData(
            courseName: name,
            teacher: teacher,
            classInfo: "",
            room: room,
            location: location,
            duration: duration
        )

        return (data, parseWeeks(weeksString: weeksString))
    }

    nonisolated private static func parseStudentBlock(_ block: Element, duration: [Int]) throws -> [(CourseData, [Int])] {
        func extractTexts(from node: Node) -> [String] {
            var results: [String] = []
            for child in node.getChildNodes() {
                if let textNode = child as? TextNode {
                    let text = textNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty && text != "\u{00A0}" {
                        results.append(text)
                    }
                } else if let el = child as? Element {
                    if el.tagName().lowercased() == "br" {
                        results.append("#BR#")
                    } else if el.tagName().lowercased() == "hr" {
                        results.append("###HR###")
                    } else {
                        results.append(contentsOf: extractTexts(from: el))
                    }
                }
            }
            return results
        }

        let extracted = extractTexts(from: block)
        var chunks: [[String]] = []
        var currentChunk: [String] = []

        for item in extracted {
            if item.contains("---") || item == "###HR###" {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                    currentChunk = []
                }
            } else if item == "#BR#" {
                continue
            } else {
                currentChunk.append(item)
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks.map { parseStudentClassBlock($0, duration: duration) }
    }

    nonisolated private static func makeEmptyWeeklyMatrix() -> [[[(CourseData, [Int])]]] {
        Array(
            repeating: Array(
                repeating: [],
                count: totalDays
            ),
            count: totalWeeks
        )
    }

    nonisolated private static func makeCourseRecord(from data: CourseData, dayOfWeek: Int, weeks: [Int]) -> ParsedCourseRecord {
        ParsedCourseRecord(
            courseName: data.courseName,
            teacher: data.teacher.isEmpty ? "未知" : data.teacher,
            classInfo: data.classInfo,
            room: data.room.isEmpty ? "未知" : data.room,
            location: data.location.isEmpty ? data.room : data.location,
            dayOfWeek: dayOfWeek,
            weeks: weeks.sorted(),
            duration: data.duration
        )
    }

    nonisolated private static func parseGraduateCourseDetails(_ raw: String, duration: [Int], dayOfWeek: Int) -> [ParsedCourseRecord] {
        let normalized = raw
            .replacingOccurrences(of: "<br/><br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let entries = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let pattern = #"(.+?)\[([^\]]*周)\](.*?)\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var records: [ParsedCourseRecord] = []

        for entry in entries {
            let compact = entry.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            let range = NSRange(compact.startIndex..., in: compact)
            for match in regex.matches(in: compact, range: range) {
                guard match.numberOfRanges >= 5,
                      let nameRange = Range(match.range(at: 1), in: compact),
                      let weeksRange = Range(match.range(at: 2), in: compact),
                      let teacherRange = Range(match.range(at: 3), in: compact),
                      let classroomRange = Range(match.range(at: 4), in: compact) else {
                    continue
                }

                let name = String(compact[nameRange])
                let weeks = parseGraduateWeeks(String(compact[weeksRange]))
                guard !name.isEmpty, !weeks.isEmpty else { continue }

                let classroom = String(compact[classroomRange])
                let building = classroom.hasPrefix("A") || classroom.hasPrefix("B") || classroom.hasPrefix("C")
                    ? "学研中心"
                    : ""

                records.append(
                    ParsedCourseRecord(
                        courseName: name,
                        teacher: String(compact[teacherRange]),
                        classInfo: "",
                        room: classroom,
                        location: building,
                        dayOfWeek: dayOfWeek,
                        weeks: weeks,
                        duration: duration
                    )
                )
            }
        }

        return records
    }

    nonisolated private static func parseGraduateTimetableRecords(json: String) throws -> [ParsedCourseRecord] {
        guard let data = json.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let payload = try JSONDecoder().decode(GraduateSchedulePayload.self, from: data)
        var records: [ParsedCourseRecord] = []

        for row in payload.rows {
            let periods = row.mc.flatMap { value -> [Int]? in
                let values = value.matches(for: #"\d+"#).compactMap(Int.init)
                return values.isEmpty ? nil : values
            } ?? []
            guard !periods.isEmpty else { continue }

            for (key, value) in row.columns where key.hasPrefix("z") && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let dayDigits = key.matches(for: #"\d+"#)
                guard let day = dayDigits.first.flatMap(Int.init),
                      (1...totalDays).contains(day) else {
                    continue
                }
                records.append(contentsOf: parseGraduateCourseDetails(value, duration: periods, dayOfWeek: day))
            }
        }

        if records.isEmpty {
            throw HTMLParserError.noTimetableCourses
        }
        return records
    }
    
    // Compare classes for continuous time merge
    nonisolated private static func compareCourseData(prev: CourseData, curr: CourseData) -> Int {
        if prev.courseName == curr.courseName &&
            prev.location == curr.location &&
            prev.room == curr.room &&
            prev.classInfo == curr.classInfo {
            
            if let last = prev.duration.last, let first = curr.duration.first, last + 1 == first {
                return 1 // Merge durations
            }
            let prevSum = prev.duration.reduce(0, +)
            let currSum = curr.duration.reduce(0, +)
            if prevSum == currSum {
                return 2 // Exact duplicate
            }
        }
        return 0
    }

    nonisolated private static func buildCourseRecords(from weeklySchedule: [[[(CourseData, [Int])]]]) throws -> [ParsedCourseRecord] {
        var uniqueCourses: [String: ParsedCourseRecord] = [:]
        for (weekIndex, weekData) in weeklySchedule.enumerated() {
            let weekNumber = weekIndex + 1
            for (dayIndex, dayCourses) in weekData.enumerated() {
                let dayOfWeek = dayIndex + 1
                for (data, _) in dayCourses {
                    let key = "\(data.courseName)|\(dayOfWeek)|\(data.duration)|\(data.room)|\(data.location)"
                    if var existing = uniqueCourses[key] {
                        if !existing.weeks.contains(weekNumber) {
                            existing.weeks.append(weekNumber)
                            existing.weeks.sort()
                            uniqueCourses[key] = existing
                        }
                    } else {
                        uniqueCourses[key] = makeCourseRecord(from: data, dayOfWeek: dayOfWeek, weeks: [weekNumber])
                    }
                }
            }
        }

        let records = Array(uniqueCourses.values)
        if records.isEmpty {
            throw HTMLParserError.noTimetableCourses
        }
        return records
    }

    nonisolated private static func parseTimetableTable(_ timetableTable: Element) throws -> [ParsedCourseRecord] {
        var rows = try timetableTable.select("tr").array()
        guard rows.count > 2 else {
            throw HTMLParserError.timetableTableNotFound
        }
        rows = Array(rows.dropFirst().dropLast())

        var weeklySchedule = makeEmptyWeeklyMatrix()

        for (rowIndex, row) in rows.enumerated() {
            guard durationSlots.indices.contains(rowIndex) else { break }

            let allDivs = try row.select("div").array()
            let blocks = stride(from: 1, to: allDivs.count, by: 2).map { allDivs[$0] }
            let duration = durationSlots[rowIndex]

            for (dayIndex, block) in blocks.enumerated() {
                guard dayIndex < totalDays else { continue }

                let parsedBlocks = try parseStudentBlock(block, duration: duration)
                for (data, weeks) in parsedBlocks {
                    guard !data.courseName.isEmpty, !weeks.isEmpty else { continue }

                    for week in weeks where (1...totalWeeks).contains(week) {
                        var existingList = weeklySchedule[week - 1][dayIndex]
                        if let previous = existingList.last {
                            let comparison = compareCourseData(prev: previous.0, curr: data)
                            if comparison == 1 {
                                var merged = previous.0
                                merged.duration.append(contentsOf: data.duration)
                                existingList[existingList.count - 1] = (merged, previous.1)
                            } else if comparison != 2 {
                                existingList.append((data, [week]))
                            }
                        } else {
                            existingList.append((data, [week]))
                        }
                        weeklySchedule[week - 1][dayIndex] = existingList
                    }
                }
            }
        }

        return try buildCourseRecords(from: weeklySchedule)
    }

    nonisolated private static func parseTimetableContentElements(_ document: Document) throws -> [ParsedCourseRecord] {
        let contentElements = try document.select("[id^=kbcontent_], .kbcontent").array()
        guard !contentElements.isEmpty else {
            throw HTMLParserError.timetableTableNotFound
        }

        var weeklySchedule = makeEmptyWeeklyMatrix()

        for element in contentElements {
            guard let placement = try parseDayAndDuration(from: element) else { continue }

            let parsedBlocks = try parseStudentBlock(element, duration: placement.duration)
            for (data, weeks) in parsedBlocks {
                guard !data.courseName.isEmpty, !weeks.isEmpty else { continue }

                for week in weeks where (1...totalWeeks).contains(week) {
                    var existingList = weeklySchedule[week - 1][placement.dayOfWeek - 1]
                    if let previous = existingList.last {
                        let comparison = compareCourseData(prev: previous.0, curr: data)
                        if comparison == 1 {
                            var merged = previous.0
                            merged.duration.append(contentsOf: data.duration)
                            existingList[existingList.count - 1] = (merged, previous.1)
                        } else if comparison != 2 {
                            existingList.append((data, [week]))
                        }
                    } else {
                        existingList.append((data, [week]))
                    }
                    weeklySchedule[week - 1][placement.dayOfWeek - 1] = existingList
                }
            }
        }

        return try buildCourseRecords(from: weeklySchedule)
    }

    nonisolated static func parseTimetableRecords(html: String) throws -> [ParsedCourseRecord] {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           trimmed.contains("\"rows\"") {
            return try parseGraduateTimetableRecords(json: trimmed)
        }

        let document = try SwiftSoup.parse(html)
        
        do {
            let records = try parseTimetableContentElements(document)
            if records.count > 3 {
                return records
            }
        } catch {
            // Ignore error and fallback to old table parser
        }

        if let timetableTable = try document.select("#kbtable").first() {
            var allRecords = try parseTimetableTable(timetableTable)
            if allRecords.isEmpty {
                allRecords = try parseTimetableContentElements(document)
            }
            return allRecords
        }

        return try parseTimetableContentElements(document)
    }

    /// 解析强智教务系统（如北京林业大学）的课程表 HTML
    static func parseTimetable(html: String) throws -> [Course] {
        try parseTimetableRecords(html: html).map { $0.makeCourse() }
    }
    
    /// 解析强智系统成绩页面HTML
    static func parseGrades(html: String) throws -> [Grade] {
        var parsedGrades: [Grade] = []
        let document = try SwiftSoup.parse(html)

        let gradeTables = try candidateDataTables(in: document).filter { table in
            let headerText = try table.select("th").array()
                .map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
            return headerText.contains("课程名称")
                && headerText.contains("成绩")
                && headerText.contains("学分")
                && (headerText.contains("开课学期") || headerText.contains("课程编号"))
        }
        let rows = try (gradeTables.first ?? document.select("#dataList").first())?.select("tr").array() ?? []

        for row in rows {
            let tds = try row.select("td")
            if tds.count >= 6 {
                let term = try tds[1].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let courseName = try tds[3].text().trimmingCharacters(in: .whitespacesAndNewlines)
                var score = try tds[4].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let credit = try tds[5].text().trimmingCharacters(in: .whitespacesAndNewlines)

                guard !term.isEmpty,
                      !courseName.isEmpty,
                      courseName != "课程名称",
                      parseCredit(credit) != nil else {
                    continue
                }

                let courseAttribute = tds.count > 7
                    ? try tds[7].text().trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                let courseCategory = tds.count > 10
                    ? try tds[10].text().trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                let type = [courseAttribute, courseCategory]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")

                if score.isEmpty || score == " " {
                    score = try tds[4].select("a").text().trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                if score.isEmpty || score == " " {
                    score = try tds[4].select("font").text().trimmingCharacters(in: .whitespacesAndNewlines)
                }

                let grade = Grade(term: term, courseName: courseName, credit: credit, score: score, type: type)
                parsedGrades.append(grade)
            }
        }
        
        return parsedGrades
    }

    static func parseExams(html: String) throws -> [ExamArrangement] {
        let document = try SwiftSoup.parse(html)
        let rows = try document.select("#dataList tr").array()
        guard !rows.isEmpty else {
            throw HTMLParserError.tableNotFound("考试安排")
        }

        let headerCells = try rows.first?.select("th,td").array().map {
            try normalizedTableCellText($0)
        } ?? []
        let headerIndex = examHeaderIndex(from: headerCells)
        var parsed: [ExamArrangement] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            let cells = try row.select("td").array().map {
                try normalizedTableCellText($0)
            }
            guard !cells.isEmpty else { continue }

            guard let exam = parseExamRow(cells, headerIndex: headerIndex, fallbackID: offset + 1) else {
                continue
            }
            parsed.append(exam)
        }

        if !rows.dropFirst().isEmpty && parsed.isEmpty {
            throw HTMLParserError.tableRowsUnparseable("考试安排")
        }

        return parsed
    }

    private static func normalizedTableCellText(_ element: Element) throws -> String {
        try element.text()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func parseTeachingPlan(html: String) throws -> [TeachingPlanSection] {
        let document = try SwiftSoup.parse(html)
        let rows = try document.select("#dataList tr").array()
        guard rows.count > 1 else {
            throw HTMLParserError.tableNotFound("教学计划")
        }

        var currentPeriod = ""
        var grouped: [String: [TeachingPlanCourse]] = [:]
        var orderedTerms: [String] = []

        for row in rows.dropFirst() {
            let cells = try row.select("td").array().map {
                try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard cells.count >= 8,
                  let id = Int(cells[0]) else {
                continue
            }

            let period = cells[1].isEmpty ? currentPeriod : cells[1]
            guard !period.isEmpty else { continue }
            currentPeriod = period

            let exam = extractPlanExamText(from: (try? row.html()) ?? "")
            let course = TeachingPlanCourse(
                id: id,
                period: period,
                name: cells[3],
                unit: cells[4],
                credit: Double(cells[5]) ?? 0,
                duration: cells[6],
                type: cells[7],
                exam: exam
            )

            if grouped[period] == nil {
                grouped[period] = []
                orderedTerms.append(period)
            }
            grouped[period, default: []].append(course)
        }

        return orderedTerms.map { term in
            TeachingPlanSection(term: term, courses: grouped[term] ?? [])
        }
    }

    private static func parseExamRow(
        _ cells: [String],
        headerIndex: [ExamColumn: Int],
        fallbackID: Int
    ) -> ExamArrangement? {
        let id = value(for: .id, in: cells, headerIndex: headerIndex)
            .flatMap { Int($0.normalizedDigitsOnly) }
            ?? Int(cells[safe: 0]?.normalizedDigitsOnly ?? "")
            ?? fallbackID

        guard let name = firstNonEmpty(
            value(for: .name, in: cells, headerIndex: headerIndex),
            cells[safe: 3],
            cells[safe: 2]
        ) else {
            return nil
        }

        let courseID = firstNonEmpty(
            value(for: .courseID, in: cells, headerIndex: headerIndex),
            cells[safe: 2],
            cells[safe: 1]
        ) ?? ""

        let location = firstNonEmpty(
            value(for: .location, in: cells, headerIndex: headerIndex),
            cells[safe: 5],
            cells.last
        ) ?? ""

        guard let time = parseExamTime(
            dateText: value(for: .date, in: cells, headerIndex: headerIndex),
            timeText: value(for: .time, in: cells, headerIndex: headerIndex),
            combinedText: firstNonEmpty(
                value(for: .combinedTime, in: cells, headerIndex: headerIndex),
                cells[safe: 4],
                cells.first { $0.contains(":") || $0.contains("：") }
            )
        ) else {
            return nil
        }

        return ExamArrangement(
            id: id,
            courseID: courseID,
            name: name,
            date: time.date,
            start: time.start,
            end: time.end,
            location: location
        )
    }

    private enum ExamColumn {
        case id
        case courseID
        case name
        case date
        case time
        case combinedTime
        case location
    }

    private static func examHeaderIndex(from headers: [String]) -> [ExamColumn: Int] {
        var result: [ExamColumn: Int] = [:]

        for (index, header) in headers.enumerated() {
            let compact = header.replacingOccurrences(of: " ", with: "")
            if compact.contains("序号") {
                result[.id] = index
            } else if compact.contains("课程编号") || compact.contains("课程代码") || compact == "课号" {
                result[.courseID] = index
            } else if compact.contains("课程名称") || compact == "课程" || compact == "科目" {
                result[.name] = index
            } else if compact.contains("考试时间") || compact.contains("时间地点") {
                result[.combinedTime] = index
            } else if compact.contains("考试日期") || compact == "日期" {
                result[.date] = index
            } else if compact == "时间" || compact.contains("考试时段") {
                result[.time] = index
            } else if compact.contains("考试地点") || compact.contains("地点") || compact.contains("教室") {
                result[.location] = index
            }
        }

        return result
    }

    private static func value(
        for column: ExamColumn,
        in cells: [String],
        headerIndex: [ExamColumn: Int]
    ) -> String? {
        guard let index = headerIndex[column], let value = cells[safe: index] else { return nil }
        return value.isEmpty ? nil : value
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func parseExamTime(
        dateText: String?,
        timeText: String?,
        combinedText: String?
    ) -> (date: String, start: String, end: String)? {
        let combined = [dateText, timeText, combinedText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .normalizedExamText

        guard let date = extractExamDate(from: combined),
              let timeRange = extractExamTimeRange(from: combined) else {
            return nil
        }

        return (date, timeRange.start, timeRange.end)
    }

    private static func extractExamDate(from text: String) -> String? {
        if let groups = firstRegexGroups(in: text, pattern: #"(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})"#),
           groups.count == 3,
           let year = Int(groups[0]),
           let month = Int(groups[1]),
           let day = Int(groups[2]) {
            return String(format: "%04d-%02d-%02d", year, month, day)
        }

        if let groups = firstRegexGroups(in: text, pattern: #"(\d{1,2})[月/-](\d{1,2})日?"#),
           groups.count == 2,
           let month = Int(groups[0]),
           let day = Int(groups[1]) {
            return String(format: "%04d-%02d-%02d", Calendar.current.component(.year, from: Date()), month, day)
        }

        return nil
    }

    private static func extractExamTimeRange(from text: String) -> (start: String, end: String)? {
        let pattern = #"(\d{1,2})[:：](\d{2})\s*(?:~|～|—|–|-|至|到)\s*(\d{1,2})[:：](\d{2})"#
        guard let groups = firstRegexGroups(in: text, pattern: pattern),
              groups.count == 4,
              let startHour = Int(groups[0]),
              let endHour = Int(groups[2]) else {
            return nil
        }

        let start = String(format: "%02d:%@", startHour, groups[1])
        let end = String(format: "%02d:%@", endHour, groups[3])
        return (start, end)
    }

    static func parseGradeRankings(html: String) throws -> [GradeRankingRecord] {
        let document = try SwiftSoup.parse(html)
        var records: [GradeRankingRecord] = []
        var summaryMajorTotal: Int?

        let pageText = try normalizedDocumentText(document)
        if let groups = firstRegexGroups(
            in: pageText,
            pattern: #"学分积为\s*([0-9.]+).*?班级排名第\s*(\d+)\s*名.*?专业排名第\s*(\d+)\s*名.*?专业总人数\s*(\d+)\s*人"#
        ),
           groups.count == 4,
           let classRank = Int(groups[1]),
           let majorRank = Int(groups[2]),
           let majorTotal = Int(groups[3]) {
            let metric = "学分积 \(groups[0])"
            summaryMajorTotal = majorTotal

            records.append(
                GradeRankingRecord(
                    term: "全部学期",
                    rankingRange: "班级排名",
                    rank: classRank,
                    totalCount: nil,
                    percentile: nil,
                    metricText: "总排名 · \(metric)",
                    rawFields: [
                        "记录类型": "总排名",
                        "范围": "全部学期",
                        "学分积": groups[0],
                        "班级排名": String(classRank)
                    ]
                )
            )
            records.append(
                GradeRankingRecord(
                    term: "全部学期",
                    rankingRange: "专业排名",
                    rank: majorRank,
                    totalCount: majorTotal,
                    percentile: Double(majorRank) / Double(majorTotal),
                    metricText: "总排名 · \(metric)",
                    rawFields: [
                        "记录类型": "总排名",
                        "范围": "全部学期",
                        "学分积": groups[0],
                        "专业排名": String(majorRank),
                        "专业总人数": String(majorTotal)
                    ]
                )
            )
        }

        for table in try candidateDataTables(in: document) {
            let rows = try table.select("tr").array()
            guard rows.count > 1 else { continue }
            let headerRow = try firstHeaderRow(
                in: rows,
                requiredHeaders: ["学年", "学分积", "班级排名", "专业排名"]
            )
            guard let headerRow else { continue }
            let header = try headerMap(from: headerRow.row)
            let headerText = header.values.joined(separator: " ")
            guard headerText.contains("学年"),
                  headerText.contains("学分积"),
                  headerText.contains("班级排名"),
                  headerText.contains("专业排名") else {
                continue
            }

            for row in rows.dropFirst(headerRow.index + 1) {
                let cells = try rowTexts(row)
                guard cells.count >= 5,
                      let termText = valueAtHeaderIndex(cells: cells, header: header, matching: ["学年"]) else {
                    continue
                }

                let term = termText.isEmpty ? "未知学年" : termText
                let creditPoint = valueAtHeaderIndex(cells: cells, header: header, matching: ["学分积"]) ?? ""
                let metric = creditPoint.isEmpty ? "学期段排名明细" : "学分积 \(creditPoint)"
                let classRank = valueAtHeaderIndex(cells: cells, header: header, matching: ["班级排名"])
                    .flatMap(extractFirstInteger(from:))
                let majorRank = valueAtHeaderIndex(cells: cells, header: header, matching: ["专业排名"])
                    .flatMap(extractFirstInteger(from:))
                let rawFields = rawFieldsFromRow(cells: cells, header: header)

                if let classRank {
                    records.append(
                        GradeRankingRecord(
                            term: term,
                            rankingRange: "班级排名",
                            rank: classRank,
                            totalCount: nil,
                            percentile: nil,
                            metricText: metric,
                            rawFields: rawFields
                        )
                    )
                }

                guard let majorRank else { continue }
                records.append(
                    GradeRankingRecord(
                        term: term,
                        rankingRange: "专业排名",
                        rank: majorRank,
                        totalCount: summaryMajorTotal,
                        percentile: summaryMajorTotal.map { Double(majorRank) / Double($0) },
                        metricText: metric,
                        rawFields: rawFields
                    )
                )
            }
        }

        guard !records.isEmpty else {
            throw HTMLParserError.tableNotFound("成绩排名")
        }

        return uniqueRankings(records)
    }

    static func parseGradeCreditSummary(html: String) throws -> GradeCreditSummary {
        let document = try SwiftSoup.parse(html)
        let pageText = try normalizedDocumentText(document)
        let officialGPA = parseOfficialDecimal(in: pageText, labels: [
            "平均学分绩点",
            "平均绩点",
            "学分绩点",
            "绩点",
            "GPA"
        ], maxValue: 5)
        let officialWeightedAverage = parseOfficialDecimal(in: pageText, labels: [
            "加权平均分",
            "加权均分",
            "平均成绩",
            "平均分"
        ], maxValue: 100)
        let officialCreditPoint = parseOfficialCreditPoint(in: pageText)

        for table in try candidateDataTables(in: document) {
            let rows = try table.select("tr").array()
            guard rows.count > 2 else { continue }

            let tableText = try normalizeProgramText(table.text())
            guard tableText.contains("所得学分"),
                  tableText.contains("必修学分"),
                  tableText.contains("专业选修"),
                  tableText.contains("公共选修") else {
                continue
            }

            let dataRows = try rows
                .map(rowTexts)
                .filter { cells in
                    cells.count >= 16
                        && extractFirstInteger(from: cells[0]) != nil
                        && parseCredit(cells[1]) != nil
                }

            guard let cells = dataRows.first else { continue }

            let publicBucketNames = [
                "人文科学",
                "社会科学",
                "数学与自然科学",
                "体育",
                "审美艺术",
                "视频课",
                "暑期课",
                "写作与沟通",
                "四史"
            ]
            let publicBuckets = publicBucketNames.enumerated().map { offset, name in
                GradeCreditBucket(
                    name: name,
                    credits: parseCredit(cells[safe: 7 + offset] ?? "") ?? 0
                )
            }

            let rawLabels = [
                "序号",
                "所得学分",
                "必修学分",
                "专业选修总计",
                "本专业选修",
                "外专业选修",
                "公共选修总计"
            ] + publicBucketNames
            var rawFields: [String: String] = [:]
            for (index, label) in rawLabels.enumerated() where cells.indices.contains(index) {
                rawFields[label] = cells[index]
            }
            appendOfficialGradeSummaryFields(
                to: &rawFields,
                officialGPA: officialGPA,
                officialWeightedAverage: officialWeightedAverage,
                officialCreditPoint: officialCreditPoint
            )

            return GradeCreditSummary(
                totalCredits: parseCredit(cells[safe: 1] ?? "") ?? 0,
                requiredCredits: parseCredit(cells[safe: 2] ?? "") ?? 0,
                professionalElectiveCredits: parseCredit(cells[safe: 3] ?? "") ?? 0,
                professionalMajorElectiveCredits: parseCredit(cells[safe: 4] ?? "") ?? 0,
                professionalCrossMajorElectiveCredits: parseCredit(cells[safe: 5] ?? "") ?? 0,
                publicElectiveCredits: parseCredit(cells[safe: 6] ?? "") ?? 0,
                officialGPA: officialGPA,
                officialWeightedAverage: officialWeightedAverage,
                officialCreditPoint: officialCreditPoint,
                publicElectiveBuckets: publicBuckets,
                rawFields: rawFields
            )
        }

        if officialGPA != nil || officialWeightedAverage != nil || officialCreditPoint != nil {
            var rawFields: [String: String] = [:]
            appendOfficialGradeSummaryFields(
                to: &rawFields,
                officialGPA: officialGPA,
                officialWeightedAverage: officialWeightedAverage,
                officialCreditPoint: officialCreditPoint
            )

            return GradeCreditSummary(
                totalCredits: 0,
                requiredCredits: 0,
                professionalElectiveCredits: 0,
                professionalMajorElectiveCredits: 0,
                professionalCrossMajorElectiveCredits: 0,
                publicElectiveCredits: 0,
                officialGPA: officialGPA,
                officialWeightedAverage: officialWeightedAverage,
                officialCreditPoint: officialCreditPoint,
                publicElectiveBuckets: [],
                rawFields: rawFields
            )
        }

        throw HTMLParserError.tableNotFound("所得学分详情")
    }

    private static func appendOfficialGradeSummaryFields(
        to rawFields: inout [String: String],
        officialGPA: Double?,
        officialWeightedAverage: Double?,
        officialCreditPoint: Double?
    ) {
        if let officialGPA {
            rawFields["官方GPA"] = String(format: "%.4f", officialGPA)
        }
        if let officialWeightedAverage {
            rawFields["官方加权均分"] = String(format: "%.4f", officialWeightedAverage)
        }
        if let officialCreditPoint {
            rawFields["官方学分积"] = String(format: "%.4f", officialCreditPoint)
        }
    }

    private static func parseOfficialCreditPoint(in text: String) -> Double? {
        parseOfficialDecimal(in: text, labels: ["学分积"], maxValue: nil)
    }

    private static func parseOfficialDecimal(in text: String, labels: [String], maxValue: Double?) -> Double? {
        for label in labels {
            let escapedLabel = NSRegularExpression.escapedPattern(for: label)
            let patterns = [
                "\(escapedLabel)\\s*(?:为|是|:|：)?\\s*([0-9]+(?:\\.[0-9]+)?)",
                "\(escapedLabel)[^0-9]{0,12}([0-9]+(?:\\.[0-9]+)?)"
            ]

            for pattern in patterns {
                guard let groups = firstRegexGroups(in: text, pattern: pattern),
                      let valueText = groups.first,
                      let value = Double(valueText),
                      value >= 0 else {
                    continue
                }
                if let maxValue, value > maxValue {
                    continue
                }
                return value
            }
        }

        return nil
    }

    static func parseGraduationRequirements(html: String) throws -> [GraduationCreditRequirement] {
        let document = try parseTrainingProgram(html: html)
        guard !document.creditRequirements.isEmpty else {
            throw HTMLParserError.tableNotFound("培养方案明细")
        }
        return document.creditRequirements
    }

    static func parseTrainingProgram(html: String) throws -> TrainingProgramDocument {
        let document = try SwiftSoup.parse(html)
        let title = try parseTrainingProgramTitle(from: document)
        let sections = try parseTrainingProgramSections(from: document)
        let requirements = try parseTrainingProgramCreditRequirements(from: document)

        guard !sections.isEmpty || !requirements.isEmpty else {
            throw HTMLParserError.tableNotFound("培养方案明细")
        }

        return TrainingProgramDocument(
            title: title,
            sections: sections,
            creditRequirements: requirements
        )
    }

    private static func uniqueRankings(_ records: [GradeRankingRecord]) -> [GradeRankingRecord] {
        var seen = Set<String>()
        var result: [GradeRankingRecord] = []

        for record in records {
            guard !seen.contains(record.id) else { continue }
            seen.insert(record.id)
            result.append(record)
        }

        return result.sorted { lhs, rhs in
            if lhs.term != rhs.term {
                return lhs.term > rhs.term
            }
            return lhs.rankingRange.localizedCompare(rhs.rankingRange) == .orderedAscending
        }
    }

    private static func normalizedDocumentText(_ document: Document) throws -> String {
        try normalizeProgramText(document.text())
    }

    private static func firstRegexGroups(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let matchRange = Range(match.range(at: index), in: text) else {
                return nil
            }
            return String(text[matchRange])
        }
    }

    private static func parseTrainingProgramTitle(from document: Document) throws -> String {
        for paragraph in try document.select("p").array() {
            let text = try normalizeProgramText(paragraph.text())
            if text.contains("专业本科培养方案") {
                return text
            }
        }

        let pageText = try normalizedDocumentText(document)
        if let groups = firstRegexGroups(in: pageText, pattern: #"([^，。；\s]{2,40}专业本科培养方案)"#),
           let title = groups.first,
           !title.isEmpty {
            return title
        }

        return "专业培养方案"
    }

    private static func parseTrainingProgramSections(from document: Document) throws -> [TrainingProgramSection] {
        var sections: [TrainingProgramSection] = []
        var currentTitle: String?
        var currentBody: [String] = []

        func flush() {
            guard let currentTitle else { return }
            let body = currentBody
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            sections.append(
                TrainingProgramSection(
                    id: "\(sections.count)-\(currentTitle)",
                    title: currentTitle,
                    body: body
                )
            )
        }

        for paragraph in try document.select("p").array() {
            guard !isInsideTable(paragraph) else { continue }

            let text = try normalizeProgramText(paragraph.text())
            guard !text.isEmpty,
                  !text.contains("专业本科培养方案") else {
                continue
            }

            if isTrainingProgramHeading(text) {
                flush()
                currentTitle = text
                currentBody = []
            } else if currentTitle != nil {
                currentBody.append(text)
            }
        }

        flush()
        return sections
    }

    private static func parseTrainingProgramCreditRequirements(from document: Document) throws -> [GraduationCreditRequirement] {
        var requirements: [GraduationCreditRequirement] = []
        var seenLabels = Set<String>()

        func appendRequirement(label: String, kind: GraduationCreditKind, credit: Double) {
            guard credit > 0, !seenLabels.contains(label) else { return }
            seenLabels.insert(label)

            let category = cleanTrainingCreditCategory(label: label, kind: kind)
            requirements.append(
                GraduationCreditRequirement(
                    id: "training-program|\(kind.rawValue)|\(label)",
                    category: category,
                    kind: kind,
                    courseName: "",
                    requiredCredits: credit,
                    plannedCredits: credit,
                    isAggregate: true
                )
            )
        }

        for table in try candidateDataTables(in: document) {
            for row in try table.select("tr").array() {
                let cells = try rowTexts(row)
                    .map { normalizeProgramText($0) }
                    .filter { !$0.isEmpty }
                guard !cells.isEmpty else { continue }

                for (index, cell) in cells.enumerated() {
                    if cell.contains("毕业生应取得总学分"),
                       let credit = creditValue(after: index, in: cells) {
                        appendRequirement(label: "毕业生应取得总学分", kind: .total, credit: credit)
                    }

                    for (label, kind) in trainingCreditLabels where cell.contains(label) {
                        if let credit = creditValue(after: index, in: cells) {
                            appendRequirement(label: label, kind: kind, credit: credit)
                        }
                    }
                }
            }
        }

        return requirements.sorted { lhs, rhs in
            trainingCreditSortOrder(lhs) < trainingCreditSortOrder(rhs)
        }
    }

    private static var trainingCreditLabels: [(label: String, kind: GraduationCreditKind)] {
        [
            ("通识选修课学分", .publicElective),
            ("通识必修课学分", .other),
            ("专业基础课学分", .other),
            ("专业核心课学分", .other),
            ("本专业选修课最低选修学分", .professionalElective),
            ("集中性实践环节学分", .other),
            ("毕业论文（设计）学分", .other),
            ("毕业论文(设计)学分", .other),
            ("拓展教育学分", .other)
        ]
    }

    private static func trainingCreditSortOrder(_ requirement: GraduationCreditRequirement) -> Int {
        if requirement.kind == .total { return 0 }
        if requirement.kind == .publicElective { return 1 }
        if requirement.kind == .professionalElective { return 2 }

        let orderedLabels = trainingCreditLabels.map(\.label)
        if let index = orderedLabels.firstIndex(where: { requirement.id.contains($0) }) {
            return index + 3
        }
        return 99
    }

    private static func creditValue(after index: Int, in cells: [String]) -> Double? {
        for value in cells.dropFirst(index + 1) {
            if isTrainingCreditLabel(value) {
                break
            }
            if let credit = parseCredit(value) {
                return credit
            }
        }

        return nil
    }

    private static func isTrainingCreditLabel(_ text: String) -> Bool {
        text.contains("毕业生应取得总学分")
            || trainingCreditLabels.contains { text.contains($0.label) }
    }

    private static func cleanTrainingCreditCategory(label: String, kind: GraduationCreditKind) -> String {
        if kind == .total {
            return "总学分"
        }

        return label
            .replacingOccurrences(of: "最低选修", with: "")
            .replacingOccurrences(of: "学分", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isTrainingProgramHeading(_ text: String) -> Bool {
        text.range(
            of: #"^[一二三四五六七八九十]+[、.．].{2,40}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isInsideTable(_ element: Element) -> Bool {
        var current = element.parent()
        while let parent = current {
            let tag = parent.tagName().lowercased()
            if tag == "td" || tag == "th" {
                return true
            }
            current = parent.parent()
        }
        return false
    }

    private static func normalizeProgramText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"(?<=\d)\s+(?=\d)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*([、，。：；（）()])\s*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func candidateDataTables(in document: Document) throws -> [Element] {
        var tables: [Element] = []
        let selectors = ["#dataList", "table.Nsb_r_list", "table"]

        for selector in selectors {
            for table in try document.select(selector).array() {
                let html = (try? table.outerHtml()) ?? UUID().uuidString
                if !tables.contains(where: { ((try? $0.outerHtml()) ?? "") == html }) {
                    tables.append(table)
                }
            }
        }

        return tables
    }

    private static func headerMap(from row: Element) throws -> [Int: String] {
        let cells = try row.select("th,td").array()
        var result: [Int: String] = [:]

        for (index, cell) in cells.enumerated() {
            let text = try cell.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                result[index] = text
            }
        }

        return result
    }

    private static func firstHeaderRow(
        in rows: [Element],
        requiredHeaders: [String]
    ) throws -> (index: Int, row: Element)? {
        for (index, row) in rows.enumerated() {
            let text = try row.select("th,td").array()
                .map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
            if requiredHeaders.allSatisfy({ text.contains($0) }) {
                return (index, row)
            }
        }

        return nil
    }

    nonisolated private static func rowTexts(_ row: Element) throws -> [String] {
        try row.select("td").array().map {
            try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func rawFieldsFromRow(cells: [String], header: [Int: String]) -> [String: String] {
        var result: [String: String] = [:]

        for (index, value) in cells.enumerated() {
            guard let key = header[index], !key.isEmpty else { continue }
            result[key] = value
        }

        return result
    }

    private static func firstValue(in rawFields: [String: String], matching names: [String]) -> String? {
        for name in names {
            let normalizedName = normalizedHeader(name)
            if let exact = rawFields.first(where: { normalizedHeader($0.key) == normalizedName })?.value,
               !exact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return exact
            }

            if let fuzzy = rawFields.first(where: { normalizedHeader($0.key).contains(normalizedName) || normalizedName.contains(normalizedHeader($0.key)) })?.value,
               !fuzzy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return fuzzy
            }
        }

        return nil
    }

    private static func valueAtHeaderIndex(cells: [String], header: [Int: String], matching names: [String]) -> String? {
        for (index, title) in header {
            let normalizedTitle = normalizedHeader(title)
            if names.contains(where: { normalizedTitle.contains(normalizedHeader($0)) }),
               cells.indices.contains(index),
               !cells[index].isEmpty {
                return cells[index]
            }
        }

        return nil
    }

    private static func normalizedHeader(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
    }

    nonisolated private static func extractFirstInteger(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\d+"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return Int(text[matchRange])
    }

    nonisolated private static func parseCredit(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "学分", with: "")
            .replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let direct = Double(normalized) {
            return direct
        }

        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#) else { return nil }
        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: range),
              let matchRange = Range(match.range, in: normalized) else {
            return nil
        }

        return Double(normalized[matchRange])
    }

    private static func inferRankingRange(from header: [Int: String], rawFields: [String: String]) -> String {
        let joined = (Array(header.values) + Array(rawFields.values)).joined(separator: " ")
        if joined.contains("专业") { return "专业排名" }
        if joined.contains("班") { return "班级排名" }
        if joined.contains("年级") { return "年级排名" }
        if joined.contains("学院") { return "学院排名" }
        return "官方排名"
    }

    private static func isAggregateRequirementRow(courseName: String, cells: [String]) -> Bool {
        let joined = cells.joined(separator: " ")
        let compactCourse = courseName.replacingOccurrences(of: " ", with: "")

        if compactCourse.isEmpty {
            return true
        }

        return compactCourse == "合计"
            || compactCourse == "小计"
            || compactCourse == "总计"
            || joined.contains("合计")
            || joined.contains("小计")
            || joined.contains("应修")
            || joined.contains("要求")
    }

    nonisolated static func parseEmptyClassrooms(html: String) throws -> [EmptyClassroom] {
        let document = try SwiftSoup.parse(html)
        let rows = try document.select("#dataList tr").array()
        guard rows.count > 4 else {
            throw HTMLParserError.tableNotFound("空教室")
        }

        let dataRows = rows.dropFirst(2).dropLast(2)
        var result: [(weight: Int, room: EmptyClassroom)] = []

        for row in dataRows {
            let texts = try row.select("td").array().map { cell in
                try normalizedClassroomCellText(cell.text())
            }
            guard texts.count > 1 else { continue }
            if texts.dropFirst().contains(where: { !$0.isEmpty }) {
                continue
            }

            if let parsed = parseClassroomRow(texts[0]) {
                result.append(parsed)
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.weight == rhs.weight {
                return lhs.room.room < rhs.room.room
            }
            return lhs.weight > rhs.weight
        }.map(\.room)
    }

    private static func extractPlanExamText(from rowHTML: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<!--.*?<td>(.*?)</td>.*?-->"#, options: [.dotMatchesLineSeparators]) else {
            return ""
        }
        let range = NSRange(rowHTML.startIndex..., in: rowHTML)
        guard let match = regex.firstMatch(in: rowHTML, options: [], range: range),
              match.numberOfRanges > 1,
              let textRange = Range(match.range(at: 1), in: rowHTML) else {
            return ""
        }
        return String(rowHTML[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func parseClassroomRow(_ text: String) -> (weight: Int, room: EmptyClassroom)? {
        let map: [String: (Int, String)] = [
            "A": (10, "学研A座"),
            "A座": (10, "学研A座"),
            "学研A": (10, "学研A座"),
            "学研A座": (10, "学研A座"),
            "学研楼A座": (10, "学研A座"),
            "B": (9, "学研B座"),
            "B座": (9, "学研B座"),
            "学研B": (9, "学研B座"),
            "学研B座": (9, "学研B座"),
            "学研楼B座": (9, "学研B座"),
            "C": (8, "学研C座"),
            "C座": (8, "学研C座"),
            "学研C": (8, "学研C座"),
            "学研C座": (8, "学研C座"),
            "学研楼C座": (8, "学研C座"),
            "第一教学楼": (8, "一教"),
            "一教学楼": (8, "一教"),
            "一教": (8, "一教"),
            "一教楼": (8, "一教"),
            "第二教学楼": (7, "二教"),
            "二教学楼": (7, "二教"),
            "二教": (7, "二教"),
            "二教楼": (7, "二教"),
            "第三教学楼": (6, "三教"),
            "三教学楼": (6, "三教"),
            "三教": (6, "三教"),
            "三教楼": (6, "三教"),
            "基础楼": (5, "基础楼"),
            "林业楼": (4, "林业楼"),
            "生物楼": (3, "生物楼"),
            "实验楼": (2, "实验楼")
        ]

        let normalizedText = normalizedClassroomCellText(text)
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
        guard let regex = try? NSRegularExpression(pattern: #"^([^\(\d]+?)(\d+[A-Za-z]?)(?:\((\d+)\s*/\s*(\d+)\))?$"#),
              let match = regex.firstMatch(in: normalizedText, range: NSRange(normalizedText.startIndex..., in: normalizedText)),
              let buildingRange = Range(match.range(at: 1), in: normalizedText),
              let roomRange = Range(match.range(at: 2), in: normalizedText) else {
            return nil
        }

        let rawBuilding = String(normalizedText[buildingRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
        let room = String(normalizedText[roomRange]).uppercased()
        guard let (weight, mappedBuilding) = map[rawBuilding] else {
            return nil
        }

        return (weight, EmptyClassroom(building: mappedBuilding, room: room))
    }

    nonisolated private static func normalizedClassroomCellText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
    }
}
