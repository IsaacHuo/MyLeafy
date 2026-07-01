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
    static let timetableColumns = ["courseName", "teacher", "classInfo", "room", "location", "dayOfWeek", "weeks", "duration"]
    static let gradeColumns = ["term", "courseName", "credit", "score", "type"]
    static let examColumns = ["courseID", "name", "date", "start", "end", "location"]

    static func parseTimetable(_ text: String) throws -> [ParsedCourseRecord] {
        try rows(from: text, requiredColumns: timetableColumns).map { row in
            let lineNumber = row.lineNumber
            guard let dayOfWeek = Int(required("dayOfWeek", in: row).digitsOnly),
                  (1...7).contains(dayOfWeek) else {
                throw CustomCampusImportError.invalidRow(lineNumber, "dayOfWeek 需要是 1 到 7。")
            }

            let weeks = try parseIntegerSequence(required("weeks", in: row), lineNumber: lineNumber, fieldName: "weeks")
            let duration = try parseIntegerSequence(required("duration", in: row), lineNumber: lineNumber, fieldName: "duration")
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
            guard !date.isEmpty, !start.isEmpty, !end.isEmpty else {
                throw CustomCampusImportError.invalidRow(row.lineNumber, "date/start/end 不能为空。")
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
        let records = parseCSVRecords(text)
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

        var result: [CSVRow] = []
        for (index, record) in records.dropFirst().enumerated() {
            var values: [String: String] = [:]
            for (columnIndex, header) in headers.enumerated() {
                values[header] = (record[safe: columnIndex] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            result.append(CSVRow(lineNumber: index + 2, values: values))
        }
        return result
    }

    private static func parseCSVRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var iterator = Array(text).makeIterator()
        var isInsideQuotes = false

        while let character = iterator.next() {
            switch character {
            case "\"":
                if isInsideQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append(next)
                    } else {
                        isInsideQuotes = false
                        switch next {
                        case ",":
                            record.append(field)
                            field = ""
                        case "\n":
                            record.append(field)
                            records.append(record)
                            record = []
                            field = ""
                        case "\r":
                            continue
                        default:
                            field.append(next)
                        }
                    }
                } else {
                    isInsideQuotes.toggle()
                }
            case "," where !isInsideQuotes:
                record.append(field)
                field = ""
            case "\n" where !isInsideQuotes:
                record.append(field)
                records.append(record)
                record = []
                field = ""
            case "\r" where !isInsideQuotes:
                continue
            default:
                field.append(character)
            }
        }

        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }

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
                .replacingOccurrences(of: "[^0-9\\-~]", with: "", options: .regularExpression)
            guard !token.isEmpty else { continue }

            if token.contains("-") || token.contains("~") {
                let parts = token.split { $0 == "-" || $0 == "~" }.compactMap { Int($0) }
                guard parts.count == 2, parts[0] <= parts[1] else {
                    throw CustomCampusImportError.invalidRow(lineNumber, "\(fieldName) 范围无效。")
                }
                numbers.append(contentsOf: parts[0]...parts[1])
            } else if let number = Int(token) {
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
    ) throws -> Int {
        let records = try CustomCampusCSVParser.parseTimetable(loadText(from: url))
        for course in existingCourses {
            modelContext.delete(course)
        }
        for course in records.map({ $0.makeCourse() }) {
            modelContext.insert(course)
        }
        try modelContext.save()
        TimetableCacheMetadata.lastSyncAt = Date()
        TimetableCacheMetadata.lastFailureMessage = nil
        LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        return records.count
    }

    static func importGrades(
        from url: URL,
        existingGrades: [Grade],
        modelContext: ModelContext
    ) throws -> Int {
        let records = try CustomCampusCSVParser.parseGrades(loadText(from: url))
        for grade in existingGrades {
            modelContext.delete(grade)
        }
        for grade in records.map({ $0.makeGrade() }) {
            modelContext.insert(grade)
        }
        try modelContext.save()
        LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        return records.count
    }

    static func importExams(from url: URL, modelContext: ModelContext) throws -> Int {
        let records = try CustomCampusCSVParser.parseExams(loadText(from: url))
        SchoolDataCache.saveExamSchedule(records)
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
    nonisolated var digitsOnly: String {
        replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
    }

    nonisolated func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
