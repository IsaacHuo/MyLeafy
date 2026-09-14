import Foundation
import SwiftSoup

nonisolated enum HTMLParserError: LocalizedError {
    case timetableTableNotFound
    case tableNotFound(String)
    case tableRowsUnparseable(String)
    
    var errorDescription: String? {
        switch self {
        case .timetableTableNotFound:
            return "未找到课表表格，页面结构可能已变更"
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

nonisolated private struct CourseMergeKey: Hashable {
    let courseName: String
    let teacher: String
    let classInfo: String
    let dayOfWeek: Int
    let duration: [Int]
    let room: String
    let location: String

    init(data: CourseData, dayOfWeek: Int) {
        courseName = data.courseName
        teacher = data.teacher
        classInfo = data.classInfo
        self.dayOfWeek = dayOfWeek
        duration = data.duration
        room = data.room
        location = data.location
    }
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

nonisolated enum TimetableParseResult: Sendable {
    case records([ParsedCourseRecord])
    case verifiedEmpty

    var records: [ParsedCourseRecord] {
        switch self {
        case .records(let records):
            return records
        case .verifiedEmpty:
            return []
        }
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

    nonisolated private static func parseGraduateTimetableResult(json: String) throws -> TimetableParseResult {
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
            guard payload.rows.isEmpty else {
                throw HTMLParserError.tableRowsUnparseable("研究生课表")
            }
            return .verifiedEmpty
        }
        return .records(records)
    }
    
    // Compare classes for continuous time merge
    nonisolated private static func compareCourseData(prev: CourseData, curr: CourseData) -> Int {
        if prev.courseName == curr.courseName &&
            prev.teacher == curr.teacher &&
            prev.location == curr.location &&
            prev.room == curr.room &&
            prev.classInfo == curr.classInfo {
            
            if let last = prev.duration.last, let first = curr.duration.first, last + 1 == first {
                return 1 // Merge durations
            }
            if prev.duration == curr.duration {
                return 2 // Exact duplicate
            }
        }
        return 0
    }

    nonisolated private static func buildCourseRecords(from weeklySchedule: [[[(CourseData, [Int])]]]) throws -> [ParsedCourseRecord] {
        var uniqueCourses: [CourseMergeKey: ParsedCourseRecord] = [:]
        for (weekIndex, weekData) in weeklySchedule.enumerated() {
            let weekNumber = weekIndex + 1
            for (dayIndex, dayCourses) in weekData.enumerated() {
                let dayOfWeek = dayIndex + 1
                for (data, _) in dayCourses {
                    let key = CourseMergeKey(data: data, dayOfWeek: dayOfWeek)
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

        return Array(uniqueCourses.values)
    }

    nonisolated private static func parseTimetableTable(_ timetableTable: Element) throws -> [ParsedCourseRecord] {
        let rows = try timetableTable.select("tr").array()
        guard let header = rows.first else {
            throw HTMLParserError.timetableTableNotFound
        }

        let headerCells = header.children().array()
        let weekdays = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
        guard headerCells.count == totalDays + 1,
              try headerCells.dropFirst().map({ try $0.text() }) == weekdays else {
            throw HTMLParserError.tableRowsUnparseable("课表")
        }

        let periodRows = try rows.dropFirst().filter { row in
            let cells = row.children().array()
            // 实验实习说明没有确定的星期和节次，不属于周课表网格。
            return try cells.first?.text().contains("实验实习安排") != true
        }
        guard periodRows.count == durationSlots.count else {
            throw HTMLParserError.tableRowsUnparseable("课表")
        }

        var weeklySchedule = makeEmptyWeeklyMatrix()

        for (rowIndex, row) in periodRows.enumerated() {
            let cells = row.children().array()
            let duration = durationSlots[rowIndex]
            // 学校把 1–2 节和第 12 节都写作“12节”，必须结合行序确认节次。
            let periodLabel = duration.map(String.init).joined() + "节"
            guard cells.count == totalDays + 1,
                  try cells[0].text().replacingOccurrences(of: "\\s+", with: "", options: .regularExpression) == periodLabel,
                  try cells.allSatisfy({ cell in
                      let colspan = try cell.attr("colspan")
                      let rowspan = try cell.attr("rowspan")
                      return (colspan.isEmpty || colspan == "1") && (rowspan.isEmpty || rowspan == "1")
                  }) else {
                throw HTMLParserError.tableRowsUnparseable("课表")
            }

            for (dayIndex, cell) in cells.dropFirst().enumerated() {
                // 同一格有简略版 kbcontent1 和详细版 kbcontent，只读取详细版。
                let blocks = try cell.select(".kbcontent").array()
                let cellText = try cell.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if blocks.isEmpty && cellText.isEmpty { continue }
                guard blocks.count == 1, let block = blocks.first else {
                    throw HTMLParserError.tableRowsUnparseable("课表")
                }
                if try block.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    guard cellText.isEmpty else {
                        throw HTMLParserError.tableRowsUnparseable("课表")
                    }
                    continue
                }

                let parsedBlocks = try parseStudentBlock(block, duration: duration)
                guard !parsedBlocks.isEmpty else {
                    throw HTMLParserError.tableRowsUnparseable("课表")
                }
                for (data, weeks) in parsedBlocks {
                    guard !data.courseName.isEmpty, weeks.contains(where: { (1...totalWeeks).contains($0) }) else {
                        throw HTMLParserError.tableRowsUnparseable("课表")
                    }

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

    nonisolated static func parseTimetableResult(html: String) throws -> TimetableParseResult {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           trimmed.contains("\"rows\"") {
            return try parseGraduateTimetableResult(json: trimmed)
        }

        let document = try SwiftSoup.parse(html)

        // 完整表格的行列是课程位置的权威来源，课程格 ID 可能是学校生成的随机编号。
        if let timetableTable = try document.select("#kbtable").first() {
            let records = try parseTimetableTable(timetableTable)
            return records.isEmpty ? .verifiedEmpty : .records(records)
        }

        let contentElements = try document.select("[id^=kbcontent_], .kbcontent").array()
        if !contentElements.isEmpty {
            let records = try parseTimetableContentElements(document)
            if !records.isEmpty {
                return .records(records)
            }
            let containsCourseContent = try contentElements
                .map { try $0.text() }
                .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !containsCourseContent else {
                throw HTMLParserError.tableRowsUnparseable("课表")
            }
            return .verifiedEmpty
        }

        throw HTMLParserError.timetableTableNotFound
    }

    nonisolated static func parseTimetableRecords(html: String) throws -> [ParsedCourseRecord] {
        try parseTimetableResult(html: html).records
    }

    /// 解析强智教务系统（如北京林业大学）的课程表 HTML
    static func parseTimetable(html: String) throws -> [Course] {
        try parseTimetableRecords(html: html).map { $0.makeCourse() }
    }
    
    /// Read portal columns by heading; course identity must survive persistence.
    static func parseGrades(html: String) throws -> [Grade] {
        let document = try SwiftSoup.parse(html)
        for table in try candidateDataTables(in: document) {
            let grid = try AcademicHTMLTable(table)
            guard let headerIndex = grid.rows.firstIndex(where: {
                $0.contains("课程名称") && $0.contains("成绩") && $0.contains("学分")
            }) else { continue }
            let header = grid.rows[headerIndex]
            func column(_ names: String...) -> Int? { AcademicHTMLTable.column(names, in: header) }
            let termColumn = column("开课学期", "学期")
            let nameColumn = column("课程名称")
            let scoreColumn = column("成绩")
            let creditColumn = column("学分")
            let codeColumn = column("课程编号", "课程代码")
            var grades: [Grade] = []
            for row in grid.rows.dropFirst(headerIndex + 1) {
                func value(_ index: Int?) -> String { AcademicHTMLTable.value(row, at: index) }
                if row.allSatisfy({ $0.isEmpty }) || row.joined().contains("暂无数据") || row.joined().contains("无记录") { continue }
                guard !value(termColumn).isEmpty, !value(nameColumn).isEmpty,
                      AcademicHTMLTable.decimal(value(creditColumn)) != nil else {
                    throw HTMLParserError.tableRowsUnparseable("成绩")
                }
                let attribute = value(column("课程属性"))
                let category = value(column("课程分类", "课程性质"))
                grades.append(Grade(
                    term: value(termColumn), courseName: value(nameColumn), credit: value(creditColumn),
                    score: value(scoreColumn), type: [attribute, category].filter { !$0.isEmpty }.joined(separator: " · "),
                    courseCode: value(codeColumn).isEmpty ? nil : value(codeColumn),
                    courseAttribute: attribute, courseCategory: category, examNature: value(column("考试性质"))
                ))
            }
            return grades
        }
        throw HTMLParserError.tableNotFound("成绩")
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
        let headerText = headerCells.joined(separator: " ")
        guard headerText.contains("课程"),
              headerText.contains("考试") || headerText.contains("考试时段") else {
            throw HTMLParserError.tableNotFound("考试安排")
        }
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

        let dataRows = try rows.dropFirst().filter { try !$0.select("td").isEmpty() }
        if parsed.isEmpty,
           !dataRows.isEmpty,
           try !rowsRepresentVerifiedEmpty(dataRows) {
            throw HTMLParserError.tableRowsUnparseable("考试安排")
        }

        return parsed
    }

    nonisolated private static func normalizedTableCellText(_ element: Element) throws -> String {
        try element.text()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    nonisolated private static let verifiedEmptyMarkers = [
        "暂无数据",
        "暂无记录",
        "没有数据",
        "没有记录",
        "无符合条件记录",
        "未查询到",
        "查询无结果"
    ]

    nonisolated private static func rowsRepresentVerifiedEmpty<S: Sequence>(_ rows: S) throws -> Bool where S.Element == Element {
        let text = try rows
            .map { try normalizedTableCellText($0) }
            .joined(separator: " ")
        if verifiedEmptyMarkers.contains(where: { text.contains($0) }) {
            return true
        }
        return text.contains("暂无")
            && ["数据", "记录", "结果", "安排"].contains(where: { text.contains($0) })
    }

    static func parseTeachingPlan(html: String) throws -> [TeachingPlanSection] {
        let document = try SwiftSoup.parse(html)
        for table in try candidateDataTables(in: document) {
            let grid = try AcademicHTMLTable(table)
            guard let headerIndex = grid.rows.firstIndex(where: {
                $0.contains("课程名称") && $0.contains("学分") && ($0.contains("开课学期") || $0.contains("学期"))
            }) else { continue }
            let header = grid.rows[headerIndex]
            func column(_ names: String...) -> Int? { AcademicHTMLTable.column(names, in: header) }
            var grouped: [String: [TeachingPlanCourse]] = [:]
            var orderedTerms: [String] = []
            var currentTerm = ""
            for row in grid.rows.dropFirst(headerIndex + 1) {
                func value(_ names: String...) -> String { AcademicHTMLTable.value(row, at: AcademicHTMLTable.column(names, in: header)) }
                if row.allSatisfy({ $0.isEmpty }) || row.joined().contains("暂无数据") || row.joined().contains("无记录") { continue }
                let period = value("开课学期", "学期").isEmpty ? currentTerm : value("开课学期", "学期")
                guard !period.isEmpty, !value("课程名称").isEmpty,
                      let credit = AcademicHTMLTable.decimal(value("学分")) else {
                    throw HTMLParserError.tableRowsUnparseable("教学计划")
                }
                currentTerm = period
                if grouped[period] == nil { orderedTerms.append(period) }
                grouped[period, default: []].append(TeachingPlanCourse(
                    id: Int(value("序号")) ?? grouped.values.reduce(0) { $0 + $1.count } + 1,
                    period: period, name: value("课程名称"), unit: value("开课单位"), credit: credit,
                    duration: value("总学时", "学时"), type: value("课程属性"), exam: value("考试性质", "考核方式"),
                    courseCode: value("课程编号", "课程代码"), courseCategory: value("课程分类", "课程性质")
                ))
            }
            return orderedTerms.map { TeachingPlanSection(term: $0, courses: grouped[$0] ?? []) }
        }
        throw HTMLParserError.tableNotFound("教学计划")
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
        guard let summaryDocument = document.copy() as? Document else {
            throw HTMLParserError.tableRowsUnparseable("成绩汇总")
        }
        // Keep inline labels and values together, excluding data tables and non-visible markup.
        try summaryDocument.select("table,script,style,template,[hidden],[aria-hidden=true]").remove()
        let summaryText = try summaryDocument.text()
        let officialGPA = try officialSummaryValue(in: document, summaryText: summaryText,
            labels: ["平均学分绩点(GPA)", "平均绩点(GPA)", "平均学分绩点", "平均绩点", "学分绩点", "GPA"], maximum: 5)
        let officialWeightedAverage = try officialSummaryValue(in: document, summaryText: summaryText,
            labels: ["加权平均分", "加权均分"], maximum: 100)
        let officialCreditPoint = try officialSummaryValue(in: document, summaryText: summaryText, labels: ["学分积"], maximum: nil)
        for table in try candidateDataTables(in: document) {
            let grid = try AcademicHTMLTable(table)
            guard let headerIndex = grid.rows.firstIndex(where: { $0.contains("所得学分") && $0.contains("必修学分") }) else { continue }
            let top = grid.rows[headerIndex]
            let totalColumn = AcademicHTMLTable.column(["所得学分"], in: top)!
            guard let dataIndex = grid.rows.indices.dropFirst(headerIndex + 1).first(where: {
                AcademicHTMLTable.decimal(AcademicHTMLTable.value(grid.rows[$0], at: totalColumn)) != nil
            }) else { throw HTMLParserError.tableRowsUnparseable("所得学分详情") }
            let cells = grid.rows[dataIndex]
            guard cells.count == top.count else { throw HTMLParserError.tableRowsUnparseable("所得学分详情") }
            let bottom = grid.rows[dataIndex - 1]
            var rawFields: [String: String] = [:]
            var buckets: [GradeCreditBucket] = []
            var professional = 0.0, major = 0.0, crossMajor = 0.0, publicTotal = 0.0, required = 0.0
            for index in top.indices {
                let group = AcademicHTMLTable.heading(top[index])
                let leaf = AcademicHTMLTable.heading(AcademicHTMLTable.value(bottom, at: index))
                let value = cells[index].isEmpty ? 0 : AcademicHTMLTable.decimal(cells[index])
                guard group != "序号" else { continue }
                guard let value else { throw HTMLParserError.tableRowsUnparseable("所得学分详情") }
                let label = group == leaf ? group : group + "/" + leaf
                rawFields[label] = cells[index]
                if group == "必修学分" { required = value }
                if group.contains("专业选修") {
                    if leaf == "总计" || leaf == "合计" { professional = value }
                    if leaf == "本专业" { major = value; rawFields["本专业选修"] = cells[index] }
                    if leaf == "外专业" { crossMajor = value }
                }
                if group.contains("公共选修") || group.contains("通识选修") {
                    if leaf == "总计" || leaf == "合计" || leaf == group { publicTotal = value; rawFields["公共选修总计"] = cells[index] }
                    else { buckets.append(GradeCreditBucket(name: bottom[index], credits: value)) }
                }
            }
            rawFields["所得学分"] = cells[totalColumn]
            appendOfficialGradeSummaryFields(to: &rawFields, officialGPA: officialGPA,
                officialWeightedAverage: officialWeightedAverage, officialCreditPoint: officialCreditPoint)
            return GradeCreditSummary(totalCredits: AcademicHTMLTable.decimal(cells[totalColumn])!, requiredCredits: required,
                professionalElectiveCredits: professional, professionalMajorElectiveCredits: major,
                professionalCrossMajorElectiveCredits: crossMajor, publicElectiveCredits: publicTotal,
                officialGPA: officialGPA, officialWeightedAverage: officialWeightedAverage, officialCreditPoint: officialCreditPoint,
                publicElectiveBuckets: buckets, rawFields: rawFields, syncedAt: Date())
        }
        guard officialGPA != nil || officialWeightedAverage != nil || officialCreditPoint != nil else {
            throw HTMLParserError.tableNotFound("所得学分详情")
        }
        var rawFields: [String: String] = [:]
        appendOfficialGradeSummaryFields(to: &rawFields, officialGPA: officialGPA,
            officialWeightedAverage: officialWeightedAverage, officialCreditPoint: officialCreditPoint)
        return GradeCreditSummary(totalCredits: 0, requiredCredits: 0, professionalElectiveCredits: 0,
            professionalMajorElectiveCredits: 0, professionalCrossMajorElectiveCredits: 0, publicElectiveCredits: 0,
            officialGPA: officialGPA, officialWeightedAverage: officialWeightedAverage, officialCreditPoint: officialCreditPoint,
            publicElectiveBuckets: [], rawFields: rawFields, syncedAt: Date())
    }

    private static func normalizedOfficialSummaryLabel(_ text: String) -> String {
        text.replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: #"\s*\(\s*GPA\s*\)"#, with: "(GPA)", options: [.regularExpression, .caseInsensitive])
    }

    private static func officialSummaryValue(in document: Document, summaryText: String, labels: [String], maximum: Double?) throws -> Double? {
        // Only exact table label/value pairs or explicit prose summaries, never ranking-table numbers.
        for row in try document.select("tr").array() {
            let cells = row.children().array()
            if cells.count == 2,
               labels.contains(normalizedOfficialSummaryLabel(AcademicHTMLTable.heading(try cells[0].text()))),
               let value = AcademicHTMLTable.decimal(try cells[1].text()), maximum.map({ value <= $0 }) ?? true {
                return value
            }
        }
        let text = normalizedOfficialSummaryLabel(summaryText)
        for label in labels {
            let pattern = NSRegularExpression.escapedPattern(for: label) + #"\s*(?:为|是|:|：)\s*([0-9]+(?:\.[0-9]+)?)"#
            if let groups = firstRegexGroups(in: text, pattern: pattern, options: .caseInsensitive), let first = groups.first,
               let value = Double(first), maximum.map({ value <= $0 }) ?? true { return value }
        }
        return nil
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
                "\(escapedLabel)\\s*(?:为|是|:|：)\\s*([0-9]+(?:\\.[0-9]+)?)"
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
            creditRequirements: requirements,
            tables: try document.select("table").array().filter { table in
                // Keep content tables once, without page-layout tables or nested duplicates.
                try table.select("table").count == 1
            }.enumerated().compactMap { index, table in
                let rows = try AcademicHTMLTable(table).rows
                guard rows.count > 1 else { return nil }
                return TrainingProgramTable(id: "table-\(index)", title: "方案表格 \(index + 1)", rows: rows)
            }
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
        var currentLinks: [TrainingProgramLink] = []

        func flush() {
            guard let currentTitle else { return }
            let body = currentBody
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            sections.append(
                TrainingProgramSection(
                    id: "\(sections.count)-\(currentTitle)",
                    title: currentTitle,
                    body: body,
                    links: currentLinks
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
                currentLinks = []
            } else if currentTitle != nil {
                let paragraphLinks = try paragraph.select("a[href]").array().compactMap { anchor -> TrainingProgramLink? in
                    let href = try anchor.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !href.isEmpty, href != "#" else { return nil }
                    let title = try normalizeProgramText(anchor.text())
                    return TrainingProgramLink(title: title, href: href)
                }

                for link in paragraphLinks where !currentLinks.contains(where: { $0.id == link.id }) {
                    currentLinks.append(link)
                }

                let paragraphWithoutLinks = try SwiftSoup.parseBodyFragment(try paragraph.html())
                try paragraphWithoutLinks.select("a").remove()
                let nonLinkText = try normalizeProgramText(paragraphWithoutLinks.text())
                if paragraphLinks.isEmpty || !nonLinkText.isEmpty {
                    currentBody.append(text)
                }
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

                    if isTrainingCreditLabel(cell), !cell.contains("毕业生应取得总学分"),
                       let credit = creditValue(after: index, in: cells) {
                        let kind: GraduationCreditKind = cell.contains("本专业选修") ? .professionalElective : .classify(cell)
                        appendRequirement(label: cell, kind: kind, credit: credit)
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
        let compact = text.replacingOccurrences(of: " ", with: "")
        return compact.count < 45 && compact.contains("学分")
            && AcademicHTMLTable.decimal(compact) == nil
            && !compact.contains("学时") && !compact.contains("占比")
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

    nonisolated static func parseEmptyClassrooms(html: String, start: Int? = nil, end: Int? = nil) throws -> [EmptyClassroom] {
        try parseClassroomAvailability(html: html).availableRooms(start: start, end: end)
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

    nonisolated static func parseClassroomRow(_ text: String) -> (weight: Int, room: EmptyClassroom)? {
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
