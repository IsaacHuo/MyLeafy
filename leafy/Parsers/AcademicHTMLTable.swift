import Foundation
import SwiftSoup

/// Expands the portal's merged cells before resolving columns by their headings.
nonisolated struct AcademicHTMLTable {
    let rows: [[String]]

    init(_ table: Element) throws {
        var grid: [[Int: String]] = []
        for (rowIndex, row) in try table.select("tr").array().enumerated() {
            while grid.count <= rowIndex { grid.append([:]) }
            var column = 0
            for cell in row.children().array() where ["td", "th"].contains(cell.tagName()) {
                while grid[rowIndex][column] != nil { column += 1 }
                let text = try cell.text().replacingOccurrences(of: "\u{00a0}", with: " ")
                    .replacingOccurrences(of: #"(?<=\d)\s+(?=\d)"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let rowSpan = min(max(Int(try cell.attr("rowspan")) ?? 1, 1), 500)
                let colSpan = min(max(Int(try cell.attr("colspan")) ?? 1, 1), 100)
                for r in rowIndex..<rowIndex + rowSpan {
                    while grid.count <= r { grid.append([:]) }
                    for c in column..<column + colSpan { grid[r][c] = text }
                }
                column += colSpan
            }
        }
        rows = grid.map { row in (0..<(row.keys.max().map { $0 + 1 } ?? 0)).map { row[$0] ?? "" } }
    }

    static func heading(_ text: String) -> String {
        text.replacingOccurrences(of: #"[\s：:]"#, with: "", options: .regularExpression)
    }

    static func column(_ names: [String], in headings: [String]) -> Int? {
        headings.firstIndex { names.contains(heading($0)) }
    }

    static func value(_ row: [String], at column: Int?) -> String {
        guard let column, row.indices.contains(column) else { return "" }
        return row[column]
    }

    static func decimal(_ text: String) -> Double? {
        let value = heading(text).replacingOccurrences(of: "学分", with: "")
        guard let number = Double(value), number.isFinite, number >= 0 else { return nil }
        return number
    }
}
