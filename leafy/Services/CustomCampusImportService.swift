import Foundation
import SwiftData

enum CustomCampusImportError: LocalizedError, Equatable {
    case emptyFile
    case missingColumns([String])
    case invalidRow(Int, String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "CSV 文件为空。"
        case .missingColumns(let columns):
            return "CSV 缺少必要列：\(columns.joined(separator: ", "))。"
        case .invalidRow(let row, let reason):
            return "CSV 第 \(row) 行格式有误：\(reason)。"
        }
    }
}

nonisolated struct CustomCampusImportedGrade: Equatable, Sendable {
    let term: String
    let courseName: String
    let credit: String
    let score: String
    let type: String

    @MainActor
    func makeGrade() -> Grade {
        Grade(term: term, courseName: courseName, credit: credit, score: score, type: type)
    }
}

nonisolated enum CustomCampusCSVParser {
    static let timetableColumns = [
        "courseName",
        "teacher",
        "classInfo",
        "room",
        "location",
        "dayOfWeek",
        "weeks",
        "duration"
    ]
    static let gradeColumns = ["term", "courseName", "credit", "score", "type"]
    static let examColumns = ["courseID", "name", "date", "start", "end", "location"]

    static func parseTimetable(_ text: String) throws -> [ParsedCourseRecord] {
        try rows(from: text, requiredColumns: timetableColumns).map { row in
            let lineNumber = row.lineNumber
            guard let dayOfWeek = Int(required("dayOfWeek", in: row)),
                  (1 ... 7).contains(dayOfWeek) else {
                throw CustomCampusImportError.invalidRow(lineNumber, "dayOfWeek 需要是 1 到 7。")
            }

            let weeks = try parseIntegerSequence(required("weeks", in: row), lineNumber: lineNumber, fieldName: "weeks")
            let duration = try parseIntegerSequence(
                required("duration", in: row),
                lineNumber: lineNumber,
                fieldName: "duration"
            )
            let courseName = required("courseName", in: row)
            guard !courseName.isEmpty else {
                throw CustomCampusImportError.invalidRow(lineNumber, "courseName 不能为空。")
            }

            return ParsedCourseRecord(
                courseName: courseName,
                teacher: required("teacher", in: row),
                classInfo: required("classInfo", in: row),
                room: required("room", in: row),
                location: required("location", in: row),
                dayOfWeek: dayOfWeek,
                weeks: weeks,
                duration: duration
            )
        }
    }

    static func parseGrades(_ text: String) throws -> [CustomCampusImportedGrade] {
        try rows(from: text, requiredColumns: gradeColumns).map { row in
            let courseName = required("courseName", in: row)
            let score = required("score", in: row)
            guard !courseName.isEmpty else {
                throw CustomCampusImportError.invalidRow(row.lineNumber, "courseName 不能为空。")
            }
            guard !score.isEmpty else {
                throw CustomCampusImportError.invalidRow(row.lineNumber, "score 不能为空。")
            }
            guard AcademicHTMLTable.decimal(required("credit", in: row)) != nil else {
                throw CustomCampusImportError.invalidRow(row.lineNumber, "credit 需要是有效的非负学分。")
            }

            return CustomCampusImportedGrade(
                term: required("term", in: row),
                courseName: courseName,
                credit: required("credit", in: row),
                score: score,
                type: required("type", in: row)
            )
        }
    }

    static func parseExams(_ text: String) throws -> [ExamArrangement] {
        try rows(from: text, requiredColumns: examColumns).enumerated().map { offset, row in
            let name = required("name", in: row)
            let date = required("date", in: row)
            let start = required("start", in: row)
            let end = required("end", in: row)
            guard !name.isEmpty else {
                throw CustomCampusImportError.invalidRow(row.lineNumber, "name 不能为空。")
            }
            func minutes(_ raw: String) -> Int? {
                let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
                      (0 ..< 24).contains(hour), (0 ..< 60).contains(minute) else { return nil }
                return hour * 60 + minute
            }
            guard UserTimetableSettings.civilDate(from: date) != nil,
                  let startMinute = minutes(start), let endMinute = minutes(end), endMinute > startMinute else {
                throw CustomCampusImportError.invalidRow(row.lineNumber, "date/start/end 需要是有效日期与起止时间。")
            }

            return ExamArrangement(
                id: offset + 1,
                courseID: required("courseID", in: row),
                name: name,
                date: date,
                start: start,
                end: end,
                location: required("location", in: row)
            )
        }
    }

    private static func rows(from text: String, requiredColumns: [String]) throws -> [CSVRow] {
        let records = try parseCSVRecords(text)
            .filter { record in
                !record.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        guard let headerRecord = records.first else {
            throw CustomCampusImportError.emptyFile
        }

        let headers = headerRecord.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingPrefix("\u{feff}")
        }
        let missing = requiredColumns.filter { !headers.contains($0) }
        guard missing.isEmpty else {
            throw CustomCampusImportError.missingColumns(missing)
        }

        guard Set(headers).count == headers.count else {
            throw CustomCampusImportError.invalidRow(1, "字段名不能重复。")
        }
        var result: [CSVRow] = []
        for (index, record) in records.dropFirst().enumerated() {
            guard record.count == headers.count else {
                throw CustomCampusImportError.invalidRow(index + 2, "字段数量与表头不一致。")
            }
            var values: [String: String] = [:]
            for (columnIndex, header) in headers.enumerated() {
                values[header] = (record[safe: columnIndex] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            result.append(CSVRow(lineNumber: index + 2, values: values))
        }
        return result
    }

    private static func parseCSVRecords(_ text: String) throws -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        let characters = Array(text)
        var index = 0
        var insideQuotes = false
        var closedQuotes = false
        while index < characters.count {
            let character = characters[index]
            if insideQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append(character); index += 1
                    } else { insideQuotes = false; closedQuotes = true }
                } else { field.append(character) }
            } else {
                switch character {
                case "\"":
                    guard field.isEmpty, !closedQuotes else {
                        throw CustomCampusImportError.invalidRow(records.count + 1, "引号位置无效。")
                    }
                    insideQuotes = true
                case ",":
                    record.append(field); field = ""; closedQuotes = false
                case "\n", "\r":
                    record.append(field); records.append(record)
                    field = ""; record = []; closedQuotes = false
                    if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
                default:
                    guard !closedQuotes || character.isWhitespace else {
                        throw CustomCampusImportError.invalidRow(records.count + 1, "引号后存在多余内容。")
                    }
                    if !closedQuotes { field.append(character) }
                }
            }
            index += 1
        }
        guard !insideQuotes else { throw CustomCampusImportError.invalidRow(records.count + 1, "引号未闭合。") }
        if !field.isEmpty || !record.isEmpty || closedQuotes { record.append(field); records.append(record) }
        return records
    }

    private static func required(_ key: String, in row: CSVRow) -> String {
        row.values[key] ?? ""
    }

    private static func parseIntegerSequence(_ value: String, lineNumber: Int, fieldName: String) throws -> [Int] {
        let normalized = value
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "｜", with: "|")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "～", with: "~")
        let tokens = normalized
            .split { character in
                character == "," || character == ";" || character == "|" || character == "/" || character.isWhitespace
            }
            .map(String.init)

        var numbers: [Int] = []
        for rawToken in tokens {
            let token = rawToken
            let maximum = fieldName == "weeks" ? SemesterConfig.timetableWeekCapacity : 24
            guard token.range(of: #"^[0-9]+(?:[-~][0-9]+)?$"#, options: .regularExpression) != nil else {
                throw CustomCampusImportError.invalidRow(lineNumber, "\(fieldName) 需要是数字或范围。")
            }

            if token.contains("-") || token.contains("~") {
                let parts = token.split { $0 == "-" || $0 == "~" }.compactMap { Int($0) }
                guard parts.count == 2, parts[0] >= 1, parts[0] <= parts[1], parts[1] <= maximum else {
                    throw CustomCampusImportError.invalidRow(lineNumber, "\(fieldName) 范围无效。")
                }
                numbers.append(contentsOf: parts[0] ... parts[1])
            } else if let number = Int(token), (1 ... maximum).contains(number) {
                numbers.append(number)
            } else {
                throw CustomCampusImportError.invalidRow(lineNumber, "\(fieldName) 需要是数字或范围。")
            }
        }

        let result = Array(Set(numbers)).sorted()
        guard !result.isEmpty else {
            throw CustomCampusImportError.invalidRow(lineNumber, "\(fieldName) 不能为空。")
        }
        return result
    }
}

@MainActor
enum CustomCampusImportService {
    static func importTimetable(
        from url: URL,
        existingCourses: [Course],
        modelContext: ModelContext
    ) async throws -> (count: Int, reminderWarning: String?) {
        let scope = CampusOperationScope()
        let records = try CustomCampusCSVParser.parseTimetable(loadText(from: url))
        let saved = try TimetableRefreshUseCase().persist(records: records, existingCourses: existingCourses,
                                                          modelContext: modelContext, allowsEmpty: true)
        let warning = await saved.reminders.restore()
        try scope.check()
        TimetableCacheMetadata.lastSyncAt = Date()
        TimetableCacheMetadata.lastFailureMessage = warning
        LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        return (records.count, warning)
    }

    static func importGrades(
        from url: URL,
        existingGrades: [Grade],
        modelContext: ModelContext
    ) throws -> Int {
        let records = try CustomCampusCSVParser.parseGrades(loadText(from: url))
        try SchoolDataSyncService.persistGrades(records.map { $0.makeGrade() }, modelContext: modelContext)
        LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        return records.count
    }

    static func importExams(from url: URL, modelContext: ModelContext) throws -> Int {
        let records = try CustomCampusCSVParser.parseExams(loadText(from: url)).map { input in
            var exam = input; exam.syncID = UUID(); exam.updatedAt = Date(); return exam
        }
        try SchoolDataCache.saveExamSchedule(records)
        LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        return records.count
    }

    private static func loadText(from url: URL) throws -> String {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private struct CSVRow {
    let lineNumber: Int
    let values: [String: String]
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    nonisolated func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
