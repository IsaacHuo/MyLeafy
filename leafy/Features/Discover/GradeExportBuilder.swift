import Foundation

enum GradeExportBuilder {
    static func makeCSVData(grades: [Grade]) -> Data {
        let effectiveCourses = EffectiveGradeCourseResolver.resolve(from: grades)
        let effectiveByID = Dictionary(uniqueKeysWithValues: effectiveCourses.map { ($0.recordID, $0) })
        let rows = grades
            .sorted { lhs, rhs in
                if lhs.term != rhs.term {
                    return lhs.term > rhs.term
                }
                return lhs.courseName.localizedCompare(rhs.courseName) == .orderedAscending
            }
            .map { grade -> [String] in
                let effectiveCourse = effectiveByID[grade.id]
                return [
                    grade.term,
                    grade.courseName,
                    grade.credit,
                    grade.score,
                    grade.type.isEmpty ? L10n.text("未分类") : grade.type,
                    effectiveCourse == nil ? L10n.text("否") : L10n.text("是"),
                    effectiveCourse.map { String($0.attemptCount) } ?? ""
                ]
            }

        let header = [
            L10n.text("学期"),
            L10n.text("课程"),
            L10n.text("学分"),
            L10n.text("成绩"),
            L10n.text("类型"),
            L10n.text("计入统计"),
            L10n.text("尝试次数")
        ]

        let csv = ([header] + rows)
            .map(csvLine)
            .joined(separator: "\n")
        return Data(("\u{FEFF}" + csv).utf8)
    }

    static func makeCSVFile(grades: [Grade]) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "leafy-grades-\(formatter.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try makeCSVData(grades: grades).write(to: url, options: .atomic)
        return url
    }

    nonisolated private static func csvLine(_ fields: [String]) -> String {
        fields
            .map { field in
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
                    return "\"\(escaped)\""
                }
                return escaped
            }
            .joined(separator: ",")
    }
}
