import Foundation

struct ComprehensiveQualityComponentExportSummary {
    let kind: ComprehensiveQualityComponentKind
    let weightPercent: Double
    let rawScore: Double?
    let peerMaxScore: Double?
    let officialStandardScore: Double?
    let standardScore: Double?
    let contribution: Double?
    let materialReady: Bool
    let evidenceCount: Int
    let note: String
}

struct ComprehensiveQualityExportSummary {
    let collegeName: String
    let cohort: String
    let rule: ComprehensiveQualityCollegeRule
    let academicStandardScore: Double?
    let componentDrafts: [ComprehensiveQualityComponentExportSummary]
    let qualityContribution: Double?
    let compositeScore: Double?
    let officialQualityScore: Double?
    let officialCompositeScore: Double?
    let note: String
}

enum ComprehensiveQualityExportBuilder {
    static func makeCSVData(summary: ComprehensiveQualityExportSummary) -> Data {
        var rows: [[String]] = [
            ["项目", "值", "备注"],
            ["学院", summary.collegeName, ""],
            ["届别", summary.cohort, "页面隐藏，沿用默认记录键"],
            ["规则来源", summary.rule.sourceTitle, summary.rule.sourceURLString],
            ["学业标准分", scoreText(summary.academicStandardScore), "按 95% 折算"],
            ["综素贡献", scoreText(summary.qualityContribution), "最多 5 分"],
            ["综合成绩", scoreText(summary.compositeScore), "本地估算"],
            ["官方综素分", scoreText(summary.officialQualityScore), ""],
            ["官方综合成绩", scoreText(summary.officialCompositeScore), ""],
            ["总备注", summary.note, ""],
            [],
            ["综素项目", "权重", "原始分", "专业最高分", "官方标准分", "估算标准分", "贡献", "材料状态", "材料数", "备注"]
        ]

        rows += summary.componentDrafts.map { component in
            [
                component.kind.title,
                percentText(component.weightPercent),
                scoreText(component.rawScore),
                scoreText(component.peerMaxScore),
                scoreText(component.officialStandardScore),
                scoreText(component.standardScore),
                scoreText(component.contribution),
                component.materialReady ? "已准备" : "未标记",
                "\(component.evidenceCount)",
                component.note
            ]
        }

        let csv = rows
            .map(csvLine)
            .joined(separator: "\n")
        return Data(("\u{FEFF}" + csv).utf8)
    }

    static func makeCSVFile(summary: ComprehensiveQualityExportSummary) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "leafy-comprehensive-quality-\(formatter.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try makeCSVData(summary: summary).write(to: url, options: .atomic)
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

    private static func scoreText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }

    private static func percentText(_ value: Double) -> String {
        value == floor(value) ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
    }
}
